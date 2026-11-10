require 'rails_helper'

RSpec.describe 'Favorite new dates', :mail do
  let(:follower) { create(:user) }

  before { SiteConfig.current }

  it 'does not email when the rolling window adds another future date' do
    event = create(:event, :weekly, start_time: 2.days.from_now)
    create(:favorite, user: follower, event: event)

    expect { event.regenerate_future_occurrences! }.not_to have_enqueued_mail(FavoriteMailer, :new_date)
  end

  it 'emails when a series that had run out of dates gets a new one' do
    event = create(:event, :weekly, start_time: 2.days.from_now)
    event.occurrences.update_all(occurs_at: 1.year.ago) # rubocop:disable Rails/SkipsModelValidations
    create(:favorite, user: follower, event: event)

    expect { event.regenerate_future_occurrences! }.to have_enqueued_mail(FavoriteMailer, :new_date).once
  end

  it 'emails a series change, not a new-date notice, when a past one-time event is scheduled again' do
    event = create(:event, start_time: 10.days.ago, duration: 60)
    create(:favorite, user: follower, event: event)

    expect { event.update!(start_time: 4.days.from_now) }
      .to have_enqueued_mail(FavoriteMailer, :series_changed).once
    expect(enqueued_jobs.count { |job| job[:args].to_s.include?('new_date') }).to eq(0)
  end
end
