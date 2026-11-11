require 'rails_helper'

RSpec.describe 'Favorites', type: :request do
  let(:event) { create(:event) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }
  let(:member) { create(:user) }

  before { SiteConfig.current }

  it 'shows a log-in link to a visitor and returns them to the event' do
    get event_path(event)

    expect(response.parsed_body.at_css('form[action="/favorites/login"][data-turbo="false"]')).to be_present

    post login_favorites_path, params: { return_to: event_path(event) }

    expect(response).to redirect_to(new_user_session_path)
    expect(session['user_return_to']).to eq(event_path(event))
  end

  { 'date' => 'Log in to follow this date', 'series' => 'Log in to follow every date' }.each do |variant, label|
    it "labels the #{variant} login control and submits it outside Turbo" do
      get event_occurrence_path(occurrence)

      frame_id = variant == 'date' ? "favorite_event_occurrence_#{occurrence.id}" : "favorite_event_#{event.id}"
      form = response.parsed_body.at_css("##{frame_id} form")
      button = form.at_css('button')
      expect(form['data-turbo']).to eq('false')
      expect(button.text.strip).to eq(label)
      expect(button['title']).to eq(label)
      expect(button['aria-label']).to eq("#{label} #{event.title}")
      expect(form.at_css('input[name="return_to"]')['value']).to eq(event_occurrence_path(occurrence))
    end
  end

  it 'returns visitors to the date after logging in' do
    post login_favorites_path, params: { return_to: event_occurrence_path(occurrence) }

    expect(response).to redirect_to(new_user_session_path)
    follow_redirect!
    post user_session_path, params: { user: { email: member.email, password: member.password } }

    expect(response).to redirect_to(event_occurrence_path(occurrence))
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

  it 'updates both date-page buttons when following every date' do
    sign_in member

    post favorites_path, params: {
      event_id: event.id,
      variant: 'series',
      context_occurrence_id: occurrence.id
    }, as: :turbo_stream

    expect(response.media_type).to eq(Mime[:turbo_stream])
    expect(response.body).to include('Following every date')
    expect(response.body).to include(ActionView::RecordIdentifier.dom_id(occurrence, :favorite))
  end

  it 'keeps compact follow buttons icon-only' do
    sign_in member

    post favorites_path, params: {
      event_id: event.id,
      event_occurrence_id: occurrence.id,
      variant: 'compact'
    }, as: :turbo_stream

    expect(response.body).to include('bi-star-fill')
    expect(response.body).not_to include('Follow this date')
  end

  it 'stops emails from the link in the message' do
    favorite = create(:favorite, user: member, event: event)
    token = favorite.generate_token_for(:unsubscribe)

    get unsubscribe_favorite_path(token)

    expect(response).to redirect_to(root_path)
    expect(Favorite.exists?(favorite.id)).to be false
  end
end
