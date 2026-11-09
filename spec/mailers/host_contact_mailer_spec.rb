require 'rails_helper'

RSpec.describe HostContactMailer, type: :mailer do
  let(:host) { create(:user, name: 'Ada Host', email: 'ada@example.com') }
  let(:event) { create(:event, user: host, title: 'Open Shop', start_time: Time.zone.parse('2026-11-12 19:00')) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }

  before { SiteConfig.current.update!(organization_name: 'Test Org') }

  describe '#notify' do
    let(:mail) { described_class.notify(host, event, 'Is the shop open?', sender: { email: 'guest@example.com', name: 'Pat' }) }

    it 'emails the host and replies to the sender' do
      expect(mail.to).to eq(['ada@example.com'])
      expect(mail.reply_to).to eq(['guest@example.com'])
      expect(mail[:reply_to].decoded).to include('Pat')
      expect(mail.subject).to eq('[Test Org] Message about Open Shop')
      expect(mail.text_part.body.decoded).to include('Pat (guest@example.com) sent a message about Open Shop')
      expect(mail.text_part.body.decoded).to include('Is the shop open?')
      expect(mail.text_part.body.decoded).to include(event_url(event))
    end

    it 'escapes HTML in the message' do
      body = described_class.notify(host, event, '<script>alert(1)</script>', sender: { email: 'guest@example.com' }).html_part.body.decoded

      expect(body).not_to include('<script>')
      expect(body).to include('alert(1)')
    end

    it 'names the date when the message is about one occurrence' do
      mail = described_class.notify(host, event, 'Running late', sender: { email: 'guest@example.com' }, occurrence: occurrence)

      expect(mail.subject).to eq('[Test Org] Message about Open Shop on Nov 12')
      expect(mail.text_part.body.decoded).to include('November 12, 2026 at 07:00 PM')
      expect(mail.text_part.body.decoded).to include(event_occurrence_url(occurrence))
    end

    it 'sends to the test address and still replies to the sender' do
      SiteConfig.current.update!(email_test_mode_enabled: true, email_test_mode_address: 'qa@example.com')
      mail = described_class.notify(host, event, 'Hello', sender: { email: 'guest@example.com', name: 'Pat' })

      expect(mail.to).to eq(['qa@example.com'])
      expect(mail.reply_to).to eq(['guest@example.com'])
      expect(mail.text_part.body.decoded).to include('TEST MODE')
    end
  end
end
