require 'rails_helper'

RSpec.describe Favorite, type: :model do
  let(:user) { create(:user) }
  let(:event) { create(:event) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }

  before { SiteConfig.current }

  it 'allows one event favorite and one date favorite for the same user' do
    create(:favorite, user: user, event: event)
    date_favorite = create(:favorite, :for_occurrence, user: user, event: event)

    expect(date_favorite).to be_occurrence_favorite
    expect(date_favorite.event_occurrence.event_id).to eq(event.id)
  end

  it 'rejects a second favorite of the same event' do
    create(:favorite, user: user, event: event)

    expect(build(:favorite, user: user, event: event)).not_to be_valid
  end

  it 'rejects a date favorite whose occurrence belongs to another event' do
    other = create(:event).occurrences.first
    favorite = build(:favorite, user: user, event: event, event_occurrence: other)

    expect(favorite).not_to be_valid
    expect(favorite.errors[:event_occurrence]).to include('must belong to the event')
  end

  it 'keeps the row when the event is soft deleted' do
    favorite = create(:favorite, user: user, event: event)

    event.destroy!

    expect(described_class.exists?(favorite.id)).to be true
    expect(described_class.upcoming_for(user)).to be_empty
  end

  describe '.covering' do
    it 'includes event followers and followers of that date' do
      event_follower = create(:user)
      date_follower = create(:user)
      stranger = create(:user)
      create(:favorite, user: event_follower, event: event)
      create(:favorite, :for_occurrence, user: date_follower, event: event, event_occurrence: occurrence)
      create(:favorite, user: stranger, event: create(:event))

      expect(described_class.covering(occurrence).pluck(:user_id)).to contain_exactly(event_follower.id, date_follower.id)
    end

    it 'skips everyone when following is turned off' do
      create(:favorite, user: user, event: event)
      SiteConfig.current.update!(favorites_enabled: false)

      expect(described_class.covering(occurrence)).to be_empty
    end
  end

  describe '.visible_follower?' do
    it 'skips someone who can no longer see a private event' do
      private_event = create(:event, :private)

      expect(described_class.visible_follower?(user, private_event)).to be false
      expect(described_class.visible_follower?(private_event.user, private_event)).to be true
    end

    it 'skips someone who turned favorite emails off' do
      user.update!(favorite_emails_enabled: false)

      expect(described_class.visible_follower?(user, event)).to be false
    end
  end

  describe '.upcoming_for' do
    it 'merges event dates and a single followed date, without duplicates' do
      later = create(:event_occurrence, event: event, occurs_at: 3.weeks.from_now)
      create(:favorite, user: user, event: event)
      create(:favorite, :for_occurrence, user: user, event: event, event_occurrence: later)

      rows = described_class.upcoming_for(user)
      expect(rows.map { |occurrence_row, source| [occurrence_row.id, source] }).to include([occurrence.id, :event], [later.id, :event])
      expect(rows.map(&:first).map(&:id).uniq.size).to eq(rows.size)
    end
  end
end
