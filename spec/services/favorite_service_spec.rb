require 'rails_helper'

RSpec.describe FavoriteService do
  let(:user) { create(:user) }
  let(:event) { create(:event, start_time: 5.days.from_now) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }

  before { SiteConfig.current }

  it 'refuses a private event the user cannot see' do
    private_event = create(:event, :private)

    expect { described_class.follow!(user, event: private_event) }.to raise_error(Pundit::NotAuthorizedError)
  end

  describe '.transfer!' do
    it 'moves a date favorite onto the postponed date' do
      favorite = create(:favorite, :for_occurrence, user: user, event: event, event_occurrence: occurrence)
      new_occurrence = nil

      expect(occurrence.postpone!(10.days.from_now, 'Room', event.user)).to be true
      new_occurrence = event.occurrences.order(:occurs_at).last

      expect(favorite.reload.event_occurrence).to eq(new_occurrence)
    end

    it 'drops the date favorite when the user already follows the event' do
      create(:favorite, user: user, event: event)
      date_favorite = create(:favorite, :for_occurrence, user: user, event: event, event_occurrence: occurrence)

      occurrence.postpone!(10.days.from_now, 'Room', event.user)

      expect(Favorite.exists?(date_favorite.id)).to be false
      expect(user.favorites.for_events.where(event: event)).to exist
    end
  end
end
