require 'rails_helper'

RSpec.describe 'Contacting hosts', :mail, type: :request do
  let(:host) { create(:user, name: 'Ada Host', email: 'ada@example.com') }
  let(:cohost) { create(:user, name: 'Casey Host', email: 'casey@example.com') }
  let(:member) { create(:user, name: 'Member Pat', email: 'member@example.com') }
  let(:event) { create(:event, :contactable, user: host, visibility: 'public', title: 'Open Shop') }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }

  def contact_params
    { email: 'guest@example.com', name: 'Pat', message: 'Is the shop open?' }
  end

  before { SiteConfig.current }

  describe 'opting in' do
    before { sign_in host }

    it 'offers the choice between RSVPs and visibility' do
      get edit_event_path(event)

      titles = Nokogiri::HTML4(response.body).at_css('.wizard-panel[data-step="4"]').css('.card-header h5').map { |node| node.text.squish }

      expect(titles).to eq(['RSVPs', 'Contact hosts', 'Visibility & Publishing'])
      expect(response.body).to include('name="event[allow_host_contact]"')
    end

    it 'saves the opt-in' do
      event.update!(allow_host_contact: false)

      patch event_path(event), params: { event: { allow_host_contact: '1' } }

      expect(event.reload.allow_host_contact).to be true
    end

    it 'saves turning contact off' do
      patch event_path(event), params: { event: { allow_host_contact: '0' } }

      expect(event.reload.allow_host_contact).to be false
    end
  end

  describe 'the contact form' do
    it 'is hidden until the event opts in' do
      event.update!(allow_host_contact: false)

      get event_path(event)
      expect(response.body).not_to include('id="host_contact_email"')

      get event_occurrence_path(occurrence)
      expect(response.body).not_to include('id="host_contact_email"')
    end

    it 'is on the event page and the date page' do
      get event_path(event)
      expect(response.body).to include(event_host_contact_path(event))
      expect(response.body).to include('id="host_contact_email"')
      expect(response.body).to include('Contact hosts')

      get event_occurrence_path(occurrence)
      expect(response.body).to include(event_occurrence_host_contact_path(occurrence))
      expect(response.body).to include('id="host_contact_email"')
    end

    it 'fills in a signed-in person' do
      sign_in member

      get event_path(event)

      email = Nokogiri::HTML4(response.body).at_css('#host_contact_email')
      expect(email['value']).to eq(member.email)
      expect(Nokogiri::HTML4(response.body).at_css('#host_contact_name')['value']).to eq(member.name)
    end

    it 'stays hidden from someone who cannot see the event' do
      event.update!(visibility: 'members')

      get event_occurrence_path(occurrence)

      expect(response.body).not_to include('id="host_contact_email"')
    end
  end

  describe 'sending a message' do
    before { event.add_host(cohost) }

    it 'emails every host from the event page and shows the default reply' do
      expect { post event_host_contact_path(event), params: contact_params }
        .to have_enqueued_mail(HostContactMailer, :notify)
        .with(host, event, 'Is the shop open?', sender: { email: 'guest@example.com', name: 'Pat' }, occurrence: nil)
        .and have_enqueued_mail(HostContactMailer, :notify)
        .with(cohost, event, 'Is the shop open?', sender: { email: 'guest@example.com', name: 'Pat' }, occurrence: nil)

      expect(flash[:notice]).to eq(SiteConfig::DEFAULT_HOST_CONTACT_RESPONSE)
      expect(response).to redirect_to(event_path(event))
    end

    it 'emails every host about the date the message came from' do
      expect { post event_occurrence_host_contact_path(occurrence), params: contact_params }
        .to have_enqueued_mail(HostContactMailer, :notify)
        .with(host, event, 'Is the shop open?', sender: { email: 'guest@example.com', name: 'Pat' }, occurrence: occurrence)
    end

    it 'shows the reply configured in settings' do
      SiteConfig.current.update!(host_contact_response: 'We passed this along. Please wait for the hosts.')

      post event_host_contact_path(event), params: contact_params
      follow_redirect!

      expect(response.body).to include('We passed this along. Please wait for the hosts.')
    end

    it 'does not email when the address is not usable' do
      expect { post event_host_contact_path(event), params: contact_params.merge(email: 'not-an-email') }
        .not_to have_enqueued_mail(HostContactMailer)

      expect(flash[:alert]).to include('valid email')
    end

    it 'does not email when the message is blank' do
      expect { post event_host_contact_path(event), params: contact_params.merge(message: '  ') }
        .not_to have_enqueued_mail(HostContactMailer)

      expect(flash[:alert]).to include("can't be blank")
    end

    it 'does not email when the event has not opted in' do
      event.update!(allow_host_contact: false)

      expect { post event_host_contact_path(event), params: contact_params }
        .not_to have_enqueued_mail(HostContactMailer)

      expect(flash[:alert]).to include('not accepting messages')
    end

    it 'pretends a honeypot submission worked' do
      expect { post event_host_contact_path(event), params: contact_params.merge(company_website: 'https://spam.test') }
        .not_to have_enqueued_mail(HostContactMailer)

      expect(flash[:notice]).to eq(SiteConfig::DEFAULT_HOST_CONTACT_RESPONSE)
    end

    it 'refuses a guest on a members-only event' do
      event.update!(visibility: 'members')

      expect { post event_host_contact_path(event), params: contact_params }
        .not_to have_enqueued_mail(HostContactMailer)

      expect(flash[:alert]).to include('not authorized')
    end

    it 'lets a signed-in member contact a members-only event' do
      event.update!(visibility: 'members')
      sign_in member

      expect { post event_host_contact_path(event), params: contact_params }
        .to have_enqueued_mail(HostContactMailer, :notify).with(
          host, event, 'Is the shop open?', sender: { email: 'guest@example.com', name: 'Pat' }, occurrence: nil
        )
    end

    it 'delivers the message to every host when the job runs' do
      perform_enqueued_jobs do
        post event_host_contact_path(event), params: contact_params
      end

      deliveries = ActionMailer::Base.deliveries
      expect(deliveries.map(&:to).flatten).to contain_exactly('ada@example.com', 'casey@example.com')
      expect(deliveries.map(&:reply_to).uniq).to eq([['guest@example.com']])
      expect(deliveries.first.body.encoded).to include('Is the shop open?')
    end
  end
end
