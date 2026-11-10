class Favorite < ApplicationRecord
  belongs_to :user
  belongs_to :event
  belongs_to :event_occurrence, optional: true

  generates_token_for :unsubscribe, expires_in: 1.year

  scope :for_events, -> { where(event_occurrence_id: nil) }
  scope :for_occurrences, -> { where.not(event_occurrence_id: nil) }
  scope :reminding, -> { where(reminders_enabled: true) }

  validate :occurrence_belongs_to_event
  validate :one_per_target

  def event_favorite?
    event_occurrence_id.nil?
  end

  def occurrence_favorite?
    event_occurrence_id.present?
  end

  # Favorites that should hear about this date: the whole event, or this date.
  def self.covering(occurrence, reminders: false, occurrence_only: false)
    return none unless emails_enabled?

    base = where(event_id: occurrence.event_id)
    base = base.reminding if reminders
    on_date = base.where(event_occurrence_id: occurrence.id)
    return on_date if occurrence_only

    on_date.or(base.where(event_occurrence_id: nil))
  end

  # Event favorites, plus favorites of dates that have not ended.
  def self.for_series(event)
    return none unless emails_enabled?

    occurrence_ids = event.occurrences.not_yet_ended.select(:id)
    where(event_id: event.id, event_occurrence_id: nil).or(where(event_occurrence_id: occurrence_ids))
  end

  def self.emails_enabled?
    SiteConfig.current&.favorites_enabled?
  end

  # One favorite per user. An event favorite wins over a date favorite.
  def self.dedupe(favorites)
    favorites.group_by(&:user_id).map do |_user_id, rows|
      rows.min_by { |favorite| favorite.event_favorite? ? 0 : 1 }
    end
  end

  def self.visible_follower?(user, event)
    user&.favorite_emails_enabled? && EventPolicy.new(user, event).show?
  end

  def self.upcoming_for(user, limit: 20)
    favorites = user.favorites.includes(:event, :event_occurrence).to_a
    favorites.select! { |favorite| favorite.event && EventPolicy.new(user, favorite.event).show? }
    event_ids = favorites.select(&:event_favorite?).map(&:event_id)
    occurrence_ids = favorites.select(&:occurrence_favorite?).map(&:event_occurrence_id)

    from_events = event_ids.empty? ? [] : listable(event_id: event_ids).limit(limit).to_a
    from_dates = occurrence_ids.empty? ? [] : listable(id: occurrence_ids).to_a
    followed_events = event_ids.to_set

    (from_events + from_dates).uniq(&:id).sort_by(&:occurs_at).first(limit).map do |occurrence|
      source = followed_events.include?(occurrence.event_id) ? :event : :date
      [occurrence, source]
    end
  end

  def self.listable(conditions)
    EventOccurrence.listable_upcoming.where(conditions).includes(:event).order(:occurs_at)
  end

  private

  def occurrence_belongs_to_event
    return if event_occurrence.nil? || event_occurrence.event_id == event_id

    errors.add(:event_occurrence, 'must belong to the event')
  end

  def one_per_target
    return if user_id.blank? || event_id.blank?

    scope = Favorite.where(user_id: user_id, event_id: event_id)
    scope = if event_occurrence_id.nil?
              scope.where(event_occurrence_id: nil)
            else
              scope.where(event_occurrence_id: event_occurrence_id)
            end
    scope = scope.where.not(id: id) if persisted?
    errors.add(:base, 'already following') if scope.exists?
  end
end
