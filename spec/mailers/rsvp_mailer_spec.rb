require 'rails_helper'

RSpec.describe RsvpMailer, type: :mailer do
  let(:event) { create(:event, :rsvp, title: 'Open Shop', start_time: 4.days.from_now) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }
  let(:rsvp) { create(:rsvp, event_occurrence: occurrence, name: 'Grace', email: 'grace@example.com') }

  before { SiteConfig.current.update!(organization_name: 'Test Org') }

  describe '#confirmed' do
    let(:mail) { described_class.confirmed(rsvp) }

    it 'includes the management link and a calendar file' do
      expect(mail.subject).to include('[Test Org]')
      expect(mail.to).to eq(['grace@example.com'])
      expect(mail.text_part.body.decoded).to include(manage_rsvp_url(rsvp.manage_token))
      expect(mail.attachments['event.ics'].body.decoded).to include('Open Shop')
    end
  end

  describe '#login_required' do
    it 'does not reveal anything except the instruction to log in' do
      mail = described_class.login_required('ada@example.com', occurrence)

      expect(mail.text_part.body.decoded).to include('Log in')
      expect(mail.to).to eq(['ada@example.com'])
    end
  end

  it 'sends to the test address when test mode is on' do
    SiteConfig.current.update!(email_test_mode_enabled: true, email_test_mode_address: 'qa@example.com')

    expect(described_class.confirmed(rsvp).to).to eq(['qa@example.com'])
  end

  describe '#occurrence_changed' do
    it 'attaches a calendar file and says to delete the old entry' do
      mail = described_class.occurrence_changed(rsvp, kind: 'rescheduled')

      expect(mail.attachments['event.ics'].body.decoded).to include('Open Shop')
      expect(mail.text_part.body.decoded).to include('delete the old entry yourself')
    end

    it 'tells a cancelled guest to RSVP again without pretending they are still signed up' do
      rsvp.update!(status: 'cancelled', cancelled_via: 'occurrence_cancelled')
      body = described_class.occurrence_changed(rsvp, kind: 'reactivated').text_part.body.decoded

      expect(body).to include('Your RSVP was not restored')
      expect(body).to include("you'll need to RSVP again")
      expect(body).to include(event_occurrence_url(occurrence))
    end
  end
end
