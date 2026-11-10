require 'rails_helper'

RSpec.describe FavoriteMailer, type: :mailer do
  let(:follower) { create(:user, email: 'follower@example.com') }
  let(:event) { create(:event, title: 'Open House', description: 'Bring a project') }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }
  let(:favorite) { create(:favorite, user: follower, event: event) }

  before { SiteConfig.current }

  describe '#reminder' do
    let(:mail) { described_class.reminder(follower, favorite, occurrence, kind: '1d') }

    it 'includes the date, a calendar file, and a way to stop following' do
      expect(mail.to).to eq(['follower@example.com'])
      expect(mail.subject).to include('Open House')
      expect(mail.body.encoded).to include('Bring a project')
      expect(mail.body.encoded).to include('Stop following')
      expect(mail['List-Unsubscribe'].value).to include('unsubscribe')
      expect(mail.attachments.map(&:filename)).to include('event.ics')
    end
  end
end
