require 'rails_helper'

RSpec.describe ScheduleNotifier, :mail do
  let(:host) { create(:user, name: 'Ada Host') }
  let(:start_time) { Time.zone.now.change(hour: 15, min: 0) + 5.days }
  let(:event) { create(:event, :rsvp, user: host, start_time: start_time, duration: 90) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }
  let!(:rsvp) { create(:rsvp, event_occurrence: occurrence, email: 'guest@example.com') }

  before { SiteConfig.current }

  it 'does not email the creator just for creating the event' do
    expect { create(:event, user: host) }.not_to have_enqueued_mail(EventHostMailer, :added)
  end

  describe 'cancelling' do
    it 'emails every host and every current RSVP, including the wait list' do
      event.add_host(create(:user, name: 'Casey Host'))
      create(:rsvp, :waitlisted, event_occurrence: occurrence, email: 'wait@example.com')
      create(:rsvp, event_occurrence: occurrence, status: 'cancelled', email: 'gone@example.com')

      expect { event.cancel!('Weather') }
        .to have_enqueued_mail(EventHostMailer, :cancelled).twice
        .and have_enqueued_mail(RsvpMailer, :occurrence_changed).twice
    end

    it 'emails hosts and RSVPs when one date is cancelled' do
      expect { occurrence.cancel!('Weather', host) }
        .to have_enqueued_mail(EventHostMailer, :cancelled).once
        .and have_enqueued_mail(RsvpMailer, :occurrence_changed).with(rsvp, kind: 'cancelled')
    end

    it 'emails hosts once when the series will not continue' do
      expect { event.update!(permanently_cancelled: true) }
        .to have_enqueued_mail(EventHostMailer, :cancelled).once
        .and have_enqueued_mail(RsvpMailer, :occurrence_changed).once
    end
  end

  describe 'postponing' do
    it 'emails hosts and RSVPs when the series is postponed' do
      expect { event.postpone!(start_time + 7.days, 'Room') }
        .to have_enqueued_mail(EventHostMailer, :postponed).once
        .and have_enqueued_mail(RsvpMailer, :occurrence_changed).with(rsvp, kind: 'postponed')
    end

    it 'emails hosts and moves the RSVP when one date is postponed' do
      expect { occurrence.postpone!(start_time + 10.days, 'Room', host) }
        .to have_enqueued_mail(EventHostMailer, :postponed).once
        .and have_enqueued_mail(RsvpMailer, :occurrence_changed).with(rsvp, kind: 'rescheduled')

      expect(rsvp.reload.event_occurrence.occurs_at).to be_within(1.minute).of(start_time + 10.days)
    end
  end

  describe 'changing the date or time' do
    it 'emails hosts once and RSVPs when the series start time changes' do
      expect { event.update!(start_time: start_time + 1.hour) }
        .to have_enqueued_mail(EventHostMailer, :rescheduled).once
        .and have_enqueued_mail(RsvpMailer, :occurrence_changed).with(rsvp, kind: 'rescheduled')

      expect(rsvp.reload.event_occurrence.occurs_at).to be_within(1.minute).of(start_time + 1.hour)
    end

    it 'keeps the RSVP when a one-time event moves to another day' do
      new_time = start_time + 3.days

      expect { event.update!(start_time: new_time) }
        .to have_enqueued_mail(RsvpMailer, :occurrence_changed).with(rsvp, kind: 'rescheduled')
        .and have_enqueued_mail(EventHostMailer, :rescheduled).once

      expect(rsvp.reload).to be_confirmed
      expect(rsvp.event_occurrence.occurs_at).to be_within(1.minute).of(new_time)
    end

    it 'emails hosts and RSVPs when the series runs longer' do
      expect { event.update!(duration: 150) }
        .to have_enqueued_mail(EventHostMailer, :rescheduled).once
        .and have_enqueued_mail(RsvpMailer, :occurrence_changed).with(rsvp, kind: 'rescheduled')
    end

    it 'emails hosts and RSVPs when one date is edited' do
      expect { occurrence.update!(occurs_at: occurrence.occurs_at + 2.hours) }
        .to have_enqueued_mail(EventHostMailer, :rescheduled).once
        .and have_enqueued_mail(RsvpMailer, :occurrence_changed).once
    end

    it 'emails hosts and RSVPs when one date runs longer' do
      expect { occurrence.update!(duration_override: 45) }
        .to have_enqueued_mail(EventHostMailer, :rescheduled).once
        .and have_enqueued_mail(RsvpMailer, :occurrence_changed).once
    end
  end

  it 'emails hosts when a date is relocated' do
    expect { occurrence.relocate!('The annex', 'Flood', host) }
      .to have_enqueued_mail(EventHostMailer, :relocated).once
      .and have_enqueued_mail(RsvpMailer, :occurrence_changed).with(rsvp, kind: 'relocated')
  end

  describe 'reactivating' do
    it 'asks previous RSVPs to sign up again and does not restore them' do
      event.cancel!('Weather')
      clear_enqueued_jobs

      expect { event.reactivate! }
        .to have_enqueued_mail(EventHostMailer, :reactivated).once
        .and have_enqueued_mail(RsvpMailer, :occurrence_changed).with(rsvp, kind: 'reactivated')

      expect(rsvp.reload).to be_cancelled
    end

    it 'does the same when one cancelled date is reactivated' do
      create(:rsvp, event_occurrence: occurrence, status: 'cancelled', cancelled_via: 'self', email: 'opted-out@example.com')
      occurrence.cancel!('Weather', host)
      clear_enqueued_jobs

      expect { occurrence.reactivate!(host) }
        .to have_enqueued_mail(RsvpMailer, :occurrence_changed).once
        .and have_enqueued_mail(RsvpMailer, :occurrence_changed).with(rsvp, kind: 'reactivated')

      expect(rsvp.reload).to be_cancelled
    end
  end

  describe 'changing the venue' do
    let(:shop) { create(:location, name: "Shop #{SecureRandom.hex(3)}") }
    let(:hall) { create(:location, name: "Hall #{SecureRandom.hex(3)}") }

    it 'emails hosts and RSVPs when the event location changes' do
      event.update!(location: shop)
      clear_enqueued_jobs

      expect { event.update!(location: hall) }
        .to have_enqueued_mail(EventHostMailer, :venue_changed).once
        .and have_enqueued_mail(RsvpMailer, :venue_changed).once
    end

    it 'leaves guests alone when their date has its own location' do
      occurrence.update!(location: shop)
      clear_enqueued_jobs

      expect { event.update!(location: hall) }
        .to have_enqueued_mail(EventHostMailer, :venue_changed).once
        .and have_enqueued_mail(RsvpMailer, :venue_changed).exactly(0)
    end

    it 'emails hosts and RSVPs when one date overrides the location' do
      expect { occurrence.update!(location: hall) }
        .to have_enqueued_mail(EventHostMailer, :venue_changed).once
        .and have_enqueued_mail(RsvpMailer, :venue_changed).once
    end
  end
end
