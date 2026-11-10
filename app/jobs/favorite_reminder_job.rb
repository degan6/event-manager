class FavoriteReminderJob < ApplicationJob
  queue_as :mailers

  def perform
    return unless Favorite.emails_enabled?

    send_kind('1d', Time.current..reminder_deadline)
    send_kind('7d', reminder_deadline.advance(seconds: 1)..7.days.from_now, occurrence_only: true)
  end

  private

  def reminder_deadline
    SiteConfig.current.favorite_reminder_hours.hours.from_now
  end

  def send_kind(kind, window, occurrence_only: false)
    EventOccurrence.listable_upcoming.where(occurs_at: window).includes(:event).find_each do |occurrence|
      next unless remindable?(occurrence)
      next if kind == '7d' && occurrence.created_at > occurrence.occurs_at - 7.days

      favorites = Favorite.covering(occurrence, reminders: true, occurrence_only: occurrence_only)
      already = FavoriteReminderDelivery.where(event_occurrence: occurrence, kind: kind).pluck(:user_id).to_set
      Favorite.dedupe(favorites.includes(:user, :event).to_a).each do |favorite|
        user = favorite.user
        next if already.include?(user.id)
        next unless Favorite.visible_follower?(user, occurrence.event)

        FavoriteNotifier.reminder(user, favorite, occurrence, kind: kind)
      end
    end
  end

  def remindable?(occurrence)
    event = occurrence.event
    event.present? && !event.deleted? && !event.draft? && event.status == 'active'
  end
end
