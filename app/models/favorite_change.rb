class FavoriteChange < ApplicationRecord
  KINDS = %w[description banner title details].freeze

  belongs_to :event
  belongs_to :event_occurrence, optional: true
  belongs_to :actor, class_name: 'User', optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :pending, -> { where(delivered_at: nil) }

  def self.record!(event:, kind:, actor:, occurrence: nil)
    return unless Favorite.emails_enabled?
    return unless Favorite.exists?(event_id: event.id)

    create!(event: event, event_occurrence: occurrence, kind: kind, actor: actor)
  end
end
