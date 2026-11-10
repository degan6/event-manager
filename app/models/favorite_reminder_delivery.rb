class FavoriteReminderDelivery < ApplicationRecord
  KINDS = %w[7d 1d].freeze

  belongs_to :user
  belongs_to :event_occurrence

  validates :kind, inclusion: { in: KINDS }
  validates :sent_at, presence: true

  def self.clear_for(occurrence)
    where(event_occurrence_id: occurrence.id).delete_all
  end
end
