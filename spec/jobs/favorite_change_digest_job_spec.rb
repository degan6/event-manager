require 'rails_helper'

RSpec.describe FavoriteChangeDigestJob, :mail, type: :job do
  let(:host) { create(:user, :can_create_events) }
  let(:follower) { create(:user) }
  let(:event) { create(:event, user: host, description: 'Original') }

  before do
    SiteConfig.current.update!(favorite_change_quiet_minutes: 0)
    create(:favorite, user: follower, event: event)
  end

  it 'sends one email after the quiet period for several edits' do
    event.current_user_for_journal = host
    event.update!(description: 'First draft')
    event.update!(description: 'Second draft', title: 'Renamed')

    expect { described_class.perform_now }.to have_enqueued_mail(FavoriteMailer, :content_changed).once
    expect(FavoriteChange.pending).to be_empty
  end

  it 'waits while the host is still editing' do
    SiteConfig.current.update!(favorite_change_quiet_minutes: 30)
    event.current_user_for_journal = host
    event.update!(description: 'Still typing')

    expect { described_class.perform_now }.not_to have_enqueued_mail(FavoriteMailer, :content_changed)
    expect(FavoriteChange.pending.count).to eq(1)
  end

  it 'does not email the person who made the change' do
    create(:favorite, user: host, event: event)
    event.current_user_for_journal = host
    event.update!(description: 'Host notes')

    expect { described_class.perform_now }.to have_enqueued_mail(FavoriteMailer, :content_changed).once
  end

  it 'ignores banner rotation and pool changes' do
    event.update!(image_selection_mode: 'cycle', image_cycle_index: 0)
    event.update!(image_cycle_index: 1)

    expect(FavoriteChange.count).to eq(0)
    expect { described_class.perform_now }.not_to have_enqueued_mail(FavoriteMailer, :content_changed)
  end

  it 'records a fixed banner change made by a host' do
    image = event.event_images.create!(position: 0, in_pool: true)
    event.current_user_for_journal = host
    event.update!(image_selection_mode: 'fixed', fixed_event_image: image)

    expect(FavoriteChange.where(kind: 'banner')).to exist
  end

  it 'records a custom banner on one date' do
    occurrence = event.occurrences.order(:occurs_at).first
    image = event.event_images.create!(position: 1, in_pool: false)
    occurrence.current_user_for_journal = host
    occurrence.update!(event_image: image, custom_event_image: true)

    expect(FavoriteChange.where(kind: 'banner', event_occurrence: occurrence)).to exist
  end
end
