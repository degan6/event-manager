require 'rails_helper'

RSpec.describe FavoriteReminderJob, :mail, type: :job do
  let(:follower) { create(:user) }
  let(:event) { create(:event, start_time: 12.hours.from_now) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }

  before { SiteConfig.current }

  it 'sends the day-before reminder once' do
    create(:favorite, user: follower, event: event)

    expect { described_class.perform_now }.to have_enqueued_mail(FavoriteMailer, :reminder)
    expect(FavoriteReminderDelivery.where(user: follower, kind: '1d')).to exist

    expect { described_class.perform_now }.not_to have_enqueued_mail(FavoriteMailer, :reminder)
  end

  it 'sends one reminder when the user follows the event and the date' do
    create(:favorite, user: follower, event: event)
    create(:favorite, :for_occurrence, user: follower, event: event, event_occurrence: occurrence)

    expect { described_class.perform_now }.to have_enqueued_mail(FavoriteMailer, :reminder).once
  end

  it 'skips someone who already has a confirmed RSVP' do
    create(:favorite, user: follower, event: event)
    create(:rsvp, event_occurrence: occurrence, user: follower, email: follower.email, name: follower.name)

    expect { described_class.perform_now }.not_to have_enqueued_mail(FavoriteMailer, :reminder)
  end

  it 'sends a one-week heads-up only for a date followed on its own' do
    series = create(:event, start_time: 3.days.from_now)
    later = series.occurrences.order(:occurs_at).first
    later.update_column(:created_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
    create(:favorite, :for_occurrence, user: follower, event: series, event_occurrence: later)
    create(:favorite, user: create(:user), event: series)

    expect { described_class.perform_now }.to have_enqueued_mail(FavoriteMailer, :reminder).once
    expect(FavoriteReminderDelivery.find_by(user: follower).kind).to eq('7d')
  end

  it 'skips the heads-up when the date was added less than a week out' do
    later = create(:event_occurrence, event: event, occurs_at: 3.days.from_now)
    create(:favorite, :for_occurrence, user: follower, event: event, event_occurrence: later)

    expect { described_class.perform_now }.not_to have_enqueued_mail(FavoriteMailer, :reminder)
  end

  it 'skips a favorite with reminders turned off' do
    create(:favorite, user: follower, event: event, reminders_enabled: false)

    expect { described_class.perform_now }.not_to have_enqueued_mail(FavoriteMailer, :reminder)
  end
end
