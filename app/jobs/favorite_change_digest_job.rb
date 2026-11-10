class FavoriteChangeDigestJob < ApplicationJob
  queue_as :mailers

  def perform
    return unless Favorite.emails_enabled?

    quiet = SiteConfig.current.favorite_change_quiet_minutes.to_i.minutes
    event_ids = FavoriteChange.pending.distinct.pluck(:event_id)
    event_ids.each do |event_id|
      changes = FavoriteChange.pending.where(event_id: event_id).includes(:event_occurrence).to_a
      next if changes.empty? || changes.map(&:created_at).max > quiet.ago

      event = Event.find_by(id: event_id)
      FavoriteNotifier.content_changed(event, changes) if event
      FavoriteChange.where(id: changes.map(&:id)).update_all(delivered_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
