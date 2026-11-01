require 'rails_helper'

RSpec.describe EventHostMailer, type: :mailer do
  let(:host) { create(:user, name: 'Ada Host', email: 'ada@example.com') }
  let(:actor) { create(:user, name: 'Casey Organizer') }
  let(:event) { create(:event, :rsvp, user: host, title: 'Open Shop', start_time: Time.zone.parse('2026-11-12 19:00')) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }

  before { SiteConfig.current.update!(organization_name: 'Test Org') }

  describe '#added' do
    let(:mail) { described_class.added(host, event, actor: actor) }

    it 'tells them who added them and links to the event' do
      expect(mail.subject).to eq("[Test Org] You're now a host of Open Shop")
      expect(mail.to).to eq(['ada@example.com'])
      expect(mail.text_part.body.decoded).to include('Casey Organizer added you as a host of Open Shop')
      expect(mail.text_part.body.decoded).to include(event_url(event))
    end
  end

  describe '#removed' do
    it 'tells them they are no longer a host' do
      body = described_class.removed(host, event, actor: actor).text_part.body.decoded

      expect(body).to include('Casey Organizer removed you as a host of Open Shop')
    end
  end

  describe '#cancelled' do
    it 'names the date when a single occurrence was cancelled' do
      body = described_class.cancelled(host, event, occurrence: occurrence, reason: 'Weather').text_part.body.decoded

      expect(body).to include('was cancelled: Weather')
      expect(body).to include('November 12, 2026')
    end
  end

  describe '#rescheduled' do
    it 'shows the previous and new start' do
      previous = event.start_time - 1.hour
      body = described_class.rescheduled(host, event, previous_start: previous, previous_duration: event.duration)
                            .text_part.body.decoded

      expect(body).to include('The schedule for Open Shop was updated')
      expect(body).to include('06:00 PM')
      expect(body).to include('07:00 PM')
    end
  end

  it 'sends to the test address when test mode is on' do
    SiteConfig.current.update!(email_test_mode_enabled: true, email_test_mode_address: 'qa@example.com')

    expect(described_class.added(host, event, actor: actor).to).to eq(['qa@example.com'])
  end
end
