require 'rails_helper'

RSpec.describe 'Favorites', type: :request do
  let(:event) { create(:event) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }
  let(:member) { create(:user) }

  before { SiteConfig.current }

  it 'shows a log-in link to a visitor and returns them to the event' do
    get event_path(event)

    expect(response.body).to include('Log in to follow')

    post login_favorites_path, params: { return_to: event_path(event) }

    expect(response).to redirect_to(new_user_session_path)
    expect(session['user_return_to']).to eq(event_path(event))
  end

  it 'lets a member follow and unfollow an event' do
    sign_in member

    expect do
      post favorites_path, params: { event_id: event.id }
    end.to change(Favorite, :count).by(1)
    expect(response).to redirect_to(event_path(event))

    get event_path(event)
    expect(response.body).to include('Following')

    follow = member.favorites.last
    expect do
      delete favorite_path(follow)
    end.to change(Favorite, :count).by(-1)
  end

  it 'lets a member follow one date from the date page' do
    sign_in member
    get event_occurrence_path(occurrence)

    expect(response.body).to include('Follow this date')
    expect(response.body).to include('Follow every date')

    expect do
      post favorites_path, params: { event_id: event.id, event_occurrence_id: occurrence.id }
    end.to change(Favorite, :count).by(1)

    expect(Favorite.find_by(user: member, event_occurrence: occurrence)).to be_present
  end

  it 'refuses a private event' do
    sign_in member
    private_event = create(:event, :private)

    post favorites_path, params: { event_id: private_event.id }

    expect(response).to redirect_to(root_path)
    expect(Favorite.count).to eq(0)
  end

  it 'hides the control when following is turned off' do
    SiteConfig.current.update!(favorites_enabled: false)
    sign_in member

    get event_path(event)

    expect(response.body).not_to include('Log in to follow')
    expect(response.body).not_to include('>Follow<')
  end

  it 'stops emails from the link in the message' do
    favorite = create(:favorite, user: member, event: event)
    token = favorite.generate_token_for(:unsubscribe)

    get unsubscribe_favorite_path(token)

    expect(response).to redirect_to(root_path)
    expect(Favorite.exists?(favorite.id)).to be false
  end
end
