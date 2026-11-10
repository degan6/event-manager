require 'rails_helper'

RSpec.describe FavoriteNotifier, :mail do
  let(:host) { create(:user, :can_create_events) }
  let(:follower) { create(:user) }
  let(:start_time) { Time.zone.now.change(hour: 15, min: 0) + 5.days }
  let(:event) { create(:event, user: host, start_time: start_time) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }

  before do
    SiteConfig.current
    create(:favorite, user: follower, event: event)
  end

  it 'emails a follower when one date is cancelled' do
    expect { occurrence.cancel!('Weather', host) }
      .to have_enqueued_mail(FavoriteMailer, :schedule_changed).once
  end

  it 'does not email a follower who already has a confirmed RSVP' do
    create(:rsvp, event_occurrence: occurrence, user: follower, email: follower.email, name: follower.name)

    expect { occurrence.cancel!('Weather', host) }
      .not_to have_enqueued_mail(FavoriteMailer, :schedule_changed)
  end

  it 'does not email the host about their own edit' do
    create(:favorite, user: host, event: event)
    occurrence.current_user_for_journal = host

    expect { occurrence.cancel!('Weather', host) }
      .to have_enqueued_mail(FavoriteMailer, :schedule_changed).once
  end

  it 'sends one series email when the schedule changes, not one per new date' do
    expect { event.update!(start_time: start_time + 1.hour) }
      .to have_enqueued_mail(FavoriteMailer, :series_changed).once
    expect(enqueued_jobs.count { |job| job[:args].to_s.include?('new_date') }).to eq(0)
  end

  it 'moves the favorite and emails once when a date is postponed' do
    date_follower = create(:user)
    favorite = create(:favorite, :for_occurrence, user: date_follower, event: event, event_occurrence: occurrence)

    expect { occurrence.postpone!(start_time + 10.days, 'Room', host) }
      .to have_enqueued_mail(FavoriteMailer, :schedule_changed).at_least(:once)

    expect(favorite.reload.event_occurrence.occurs_at).to be_within(1.minute).of(start_time + 10.days)
  end

  it 'keeps a date favorite when a one-time event moves to another day' do
    favorite = create(:favorite, :for_occurrence, user: create(:user), event: event, event_occurrence: occurrence)
    new_time = start_time + 3.days

    event.update!(start_time: new_time)

    expect(favorite.reload.event_occurrence).to be_present
    expect(favorite.event_occurrence.occurs_at).to be_within(1.minute).of(new_time)
    expect(favorite.event_occurrence.status).to eq('active')
  end

  it 'still emails someone whose date was removed by a schedule edit' do
    series = create(:event, :weekly, user: host, start_time: start_time)
    followed = series.occurrences.order(:occurs_at).second
    date_follower = create(:user)
    create(:favorite, :for_occurrence, user: date_follower, event: series, event_occurrence: followed)
    moved = start_time + 1.day
    rule = Event.build_schedule(moved, 'weekly', { days: [moved.wday] }).to_yaml

    expect { series.update!(start_time: moved, recurrence_rule: rule) }
      .to have_enqueued_mail(FavoriteMailer, :series_changed)
  end

  it 'does not send a second reminder after the first one is claimed' do
    favorite = follower.favorites.find_by!(event: event, event_occurrence_id: nil)
    described_class.reminder(follower, favorite, occurrence, kind: '1d')
    clear_enqueued_jobs

    expect { described_class.reminder(follower, favorite, occurrence, kind: '1d') }
      .not_to have_enqueued_mail(FavoriteMailer, :reminder)
  end

  it 'stays quiet while occurrence mail is silenced' do
    ScheduleNotifier.silence_occurrence_hosts do
      expect { occurrence.cancel!('Weather', host) }
        .not_to have_enqueued_mail(FavoriteMailer, :schedule_changed)
    end
  end
end
