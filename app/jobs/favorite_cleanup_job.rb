class FavoriteCleanupJob < ApplicationJob
  queue_as :default

  def perform
    cutoff = 90.days.ago
    FavoriteChange.where(delivered_at: ..cutoff).delete_all
    FavoriteReminderDelivery.where(sent_at: ..cutoff).delete_all
  end
end
