require 'rails_helper'

RSpec.describe 'EventHosts', type: :request do
  let(:creator) { create(:user, :can_create_events) }
  let(:event) { create(:event, user: creator) }
  let(:other_user) { create(:user) }

  # The rest of these examples lean on this, so state it outright.
  it 'starts with the creator as the only host' do
    expect(event.hosts).to contain_exactly(creator)
  end

  describe 'POST /events/:event_id/event_hosts' do
    context 'as a host of the event' do
      before { sign_in creator }

      it 'adds the user as a host' do
        expect { post event_event_hosts_path(event), params: { user_id: other_user.id } }
          .to change { event.reload.hosts.include?(other_user) }.from(false).to(true)

        expect(response).to redirect_to(event)
        expect(flash[:notice]).to include(other_user.name)
      end

      it 'journals the addition' do
        expect { post event_event_hosts_path(event), params: { user_id: other_user.id } }
          .to change { EventJournal.where(event: event, action: 'host_added').count }.by(1)

        journal = EventJournal.where(event: event, action: 'host_added').last
        expect(journal.user).to eq(creator)
        expect(journal.change_data['added_host']).to eq(other_user.name)
      end

      it 'reports when the user is already a host' do
        event.add_host(other_user)

        expect { post event_event_hosts_path(event), params: { user_id: other_user.id } }
          .not_to(change { event.reload.hosts.count })

        expect(response).to redirect_to(event)
        expect(flash[:alert]).to include('is already a host')
      end

      it 'does not journal a duplicate addition' do
        event.add_host(other_user)

        expect { post event_event_hosts_path(event), params: { user_id: other_user.id } }
          .not_to change(EventJournal, :count)
      end

      it 'falls back to the email when the user has no name' do
        nameless = create(:user, name: nil)

        post event_event_hosts_path(event), params: { user_id: nameless.id }

        expect(flash[:notice]).to include(nameless.email)
      end

      it 'emails the person who was added and the other hosts', :mail do
        expect { post event_event_hosts_path(event), params: { user_id: other_user.id } }
          .to have_enqueued_mail(EventHostMailer, :added).once
          .and have_enqueued_mail(EventHostMailer, :roster_changed).once
      end

      it 'does not email anyone when the person is already a host', :mail do
        event.add_host(other_user)

        expect { post event_event_hosts_path(event), params: { user_id: other_user.id } }
          .not_to have_enqueued_mail(EventHostMailer, :added)
        expect { post event_event_hosts_path(event), params: { user_id: other_user.id } }
          .not_to have_enqueued_mail(EventHostMailer, :roster_changed)
      end

      it 'finds the event by slug' do
        post event_event_hosts_path(event.slug), params: { user_id: other_user.id }

        expect(event.reload.hosts).to include(other_user)
      end
    end

    context 'as an admin who is not a host' do
      it 'is allowed' do
        sign_in create(:user, :admin)

        post event_event_hosts_path(event), params: { user_id: other_user.id }

        expect(event.reload.hosts).to include(other_user)
      end
    end

    context 'as a signed-in user who does not host the event' do
      it 'refuses and leaves the hosts alone' do
        sign_in other_user

        expect { post event_event_hosts_path(event), params: { user_id: other_user.id } }
          .not_to(change { event.reload.hosts.count })

        expect(response).to redirect_to(event)
        expect(flash[:alert]).to include('not authorized')
      end
    end

    context 'when signed out' do
      it 'requires sign in' do
        expect { post event_event_hosts_path(event), params: { user_id: other_user.id } }
          .not_to(change { event.reload.hosts.count })

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'DELETE /events/:event_id/event_hosts/:id' do
    before { sign_in creator }

    it 'removes a co-host' do
      event.add_host(other_user)

      expect { delete event_event_host_path(event, other_user) }
        .to change { event.reload.hosts.include?(other_user) }.from(true).to(false)

      expect(response).to redirect_to(event)
      expect(flash[:notice]).to eq('Host was removed.')
    end

    it 'journals the removal' do
      event.add_host(other_user)

      expect { delete event_event_host_path(event, other_user) }
        .to change { EventJournal.where(event: event, action: 'host_removed').count }.by(1)

      journal = EventJournal.where(event: event, action: 'host_removed').last
      expect(journal.change_data['removed_host']).to eq(other_user.name)
    end

    it 'refuses to remove the only host' do
      expect { delete event_event_host_path(event, creator) }
        .not_to(change { event.reload.hosts.count })

      expect(response).to redirect_to(event)
      expect(flash[:alert]).to include('must remain as a host')
    end

    it 'emails the person who was removed and the hosts who remain', :mail do
      event.add_host(other_user)

      expect { delete event_event_host_path(event, other_user) }
        .to have_enqueued_mail(EventHostMailer, :removed).once
        .and have_enqueued_mail(EventHostMailer, :roster_changed).once
    end

    it 'does not email when the only host cannot be removed', :mail do
      expect { delete event_event_host_path(event, creator) }
        .not_to have_enqueued_mail(EventHostMailer, :removed)
    end

    it 'lets the creator be removed once a co-host exists' do
      event.add_host(other_user)

      delete event_event_host_path(event, creator)

      expect(event.reload.hosts).to contain_exactly(other_user)
    end

    it 'reports when the user is not a host' do
      event.add_host(other_user)
      bystander = create(:user)

      expect { delete event_event_host_path(event, bystander) }
        .not_to(change { event.reload.hosts.count })

      expect(flash[:alert]).to include('Could not remove host')
    end

    context 'as a signed-in user who does not host the event' do
      it 'refuses' do
        event.add_host(other_user)
        sign_in create(:user)

        expect { delete event_event_host_path(event, other_user) }
          .not_to(change { event.reload.hosts.count })

        expect(flash[:alert]).to include('not authorized')
      end
    end

    context 'when signed out' do
      it 'requires sign in' do
        event.add_host(other_user)
        sign_out creator

        delete event_event_host_path(event, other_user)

        expect(response).to redirect_to(new_user_session_path)
        expect(event.reload.hosts).to include(other_user)
      end
    end
  end
end
