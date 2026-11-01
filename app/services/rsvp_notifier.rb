class RsvpNotifier
  class << self
    def confirm_email(rsvp) = deliver(:confirm_email, rsvp)
    def confirmed(rsvp) = deliver(:confirmed, rsvp)
    def waitlisted(rsvp) = deliver(:waitlisted, rsvp)
    def spot_open(rsvp) = deliver(:spot_open, rsvp)
    def spot_held(rsvp) = deliver(:spot_held, rsvp)
    def offer_reminder(rsvp) = deliver(:offer_reminder, rsvp)
    def cancelled_by_host(rsvp) = deliver(:cancelled_by_host, rsvp)

    def reminder(rsvp, kind:, nag: false)
      return if skip?(rsvp)

      RsvpMailer.reminder(rsvp, kind: kind, nag: nag).deliver_later
    end

    def occurrence_changed(rsvp, kind)
      return if skip?(rsvp)

      RsvpMailer.occurrence_changed(rsvp, kind: kind).deliver_later
    end

    def venue_changed(rsvp, previous_name:)
      return if skip?(rsvp)

      RsvpMailer.venue_changed(rsvp, previous_name: previous_name).deliver_later
    end

    def login_required(email, occurrence)
      RsvpMailer.login_required(email, occurrence).deliver_later
    end

    def host_activity(rsvp, action)
      event = rsvp.event_occurrence.event
      event.event_hosts.where(notify_on_rsvp: true).includes(:user).find_each do |membership|
        RsvpHostMailer.rsvp_activity(membership.user, rsvp, action).deliver_later
      end
    end

    def resend(rsvp)
      case rsvp.status
      when 'pending' then confirm_email(rsvp)
      when 'confirmed' then confirmed(rsvp)
      when 'waitlisted' then rsvp.holding_offer? ? spot_held(rsvp) : waitlisted(rsvp)
      end
    end

    private

    def deliver(message, rsvp)
      return if skip?(rsvp)

      RsvpMailer.public_send(message, rsvp).deliver_later
    end

    def skip?(rsvp)
      rsvp.email.blank? || rsvp.anonymized?
    end
  end
end
