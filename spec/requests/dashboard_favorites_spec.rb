require 'rails_helper'

RSpec.describe 'Dashboard favorites', type: :request do
  let(:member) { create(:user) }
  let(:event) { create(:event, title: 'Open House', start_time: 4.days.from_now) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }

  before do
    SiteConfig.current
    sign_in member
  end

  it 'points an empty dashboard at the event list' do
    get dashboard_path

    expect(response.body).to include('Browse events')
  end

  it 'lists upcoming dates from an event favorite and a single date' do
    other = create(:event, title: 'Shop Night', start_time: 6.days.from_now)
    create(:favorite, user: member, event: event)
    create(:favorite, :for_occurrence, user: member, event: other, event_occurrence: other.occurrences.order(:occurs_at).first)
    create(:rsvp, event_occurrence: occurrence, user: member, email: member.email, name: member.name)

    get dashboard_path

    expect(response.body).to include('My Favorites')
    expect(response.body).to include('Open House')
    expect(response.body).to include('Shop Night')
    expect(response.body).to include('Following event')
    expect(response.body).to include('Following this date')
    expect(response.body).to include('RSVP')
  end

  it 'turns reminders off for one favorite' do
    favorite = create(:favorite, user: member, event: event)

    patch reminders_favorite_path(favorite)

    expect(favorite.reload.reminders_enabled).to be false
    expect(Favorite.exists?(favorite.id)).to be true
  end
end
