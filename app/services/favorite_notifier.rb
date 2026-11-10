class FavoriteNotifier
  SCHEDULE_KINDS = %w[cancelled postponed relocated rescheduled reactivated resumed venue].freeze

  class << self
    def date_changed(occurrence, kind, actor: nil, **details)
      return if silenced?

      each_follower(Favorite.covering(occurrence), actor) do |user, favorite|
        next if told_by_rsvp?(user, occurrence)

        FavoriteMailer.schedule_changed(user, favorite, occurrence, kind, details).deliver_later
      end
    end

    def series_changed(event, kind, actor: nil, **details)
      dates = event.occurrences.not_yet_ended.to_a
      each_follower(Favorite.for_series(event), actor) do |user, favorite|
        next if dates.one? && told_by_rsvp?(user, dates.first)

        FavoriteMailer.series_changed(user, favorite, event, kind, details).deliver_later
      end
    end

    def content_changed(event, changes)
      grouped = changes.group_by(&:event_occurrence_id)
      recipients = {}

      add_recipients(recipients, Favorite.for_series(event), grouped[nil]) if grouped[nil].present?
      grouped.each do |occurrence_id, rows|
        next if occurrence_id.nil?

        occurrence = EventOccurrence.find_by(id: occurrence_id)
        next if occurrence.nil?

        add_recipients(recipients, Favorite.covering(occurrence), rows)
      end

      recipients.each_value do |row|
        next if row[:changes].all? { |change| change.actor_id == row[:user].id }

        FavoriteMailer.content_changed(row[:user], row[:favorite], event, changes: row[:changes]).deliver_later
      end
    end

    def reminder(user, favorite, occurrence, kind:)
      return if told_by_rsvp?(user, occurrence)

      # Claim the send before enqueueing. Overlapping runs then lose the unique
      # insert instead of both delivering a message.
      FavoriteReminderDelivery.create!(user: user, event_occurrence: occurrence, kind: kind, sent_at: Time.current)
      FavoriteMailer.reminder(user, favorite, occurrence, kind: kind).deliver_later
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def new_date(event, occurrence)
      each_follower(Favorite.for_series(event), nil) do |user, favorite|
        FavoriteMailer.new_date(user, favorite, occurrence).deliver_later
      end
    end

    # A new date is announced only when the event had nothing coming up.
    # Schedule edits run inside ScheduleNotifier.silence_occurrence_hosts and
    # send one series email instead.
    def consider_new_date(event, had_upcoming:)
      return if had_upcoming || silenced?
      return unless event.status == 'active' && !event.draft?

      occurrence = event.occurrences.listable_upcoming.order(:occurs_at).first
      new_date(event, occurrence) if occurrence
    end

    private

    def silenced?
      Thread.current[:silence_occurrence_host_mail]
    end

    def each_follower(scope, actor)
      Favorite.dedupe(scope.includes(:user, :event).to_a).each do |favorite|
        user = favorite.user
        next unless Favorite.visible_follower?(user, favorite.event)
        next if actor && user.id == actor.id

        yield user, favorite
      end
    end

    def add_recipients(recipients, scope, changes)
      Favorite.dedupe(scope.includes(:user, :event).to_a).each do |favorite|
        user = favorite.user
        next unless Favorite.visible_follower?(user, favorite.event)

        row = recipients[user.id] ||= { user: user, favorite: favorite, changes: [] }
        row[:favorite] = favorite if favorite.event_favorite?
        row[:changes] |= changes
      end
    end

    # RSVP mail already covers a confirmed guest, and a cancellation email
    # goes out just before the favorite email.
    def told_by_rsvp?(user, occurrence)
      occurrence.rsvps.where(user: user).exists?(
        ["status = 'confirmed' OR (cancelled_via = 'occurrence_cancelled' AND cancelled_at > ?)", 10.minutes.ago]
      )
    end
  end
end
