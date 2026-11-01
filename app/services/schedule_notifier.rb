# Emails hosts and, where a series-level change would otherwise be silent,
# the people who have RSVPed. Per-date guest mail for a cancellation,
# postponement, or clock change already lives in RsvpLifecycle.
class ScheduleNotifier
  class << self
    # A series edit moves every future date's clock time. Hosts get one summary
    # after the save instead of one message per date. Dates that are dropped
    # while people are still RSVPed pass force: true and still email the hosts.
    def silence_occurrence_hosts
      previous = Thread.current[:silence_occurrence_host_mail]
      Thread.current[:silence_occurrence_host_mail] = true
      yield
    ensure
      Thread.current[:silence_occurrence_host_mail] = previous
    end

    def host_added(event, user, actor:)
      EventHostMailer.added(user, event, actor: actor).deliver_later if user.email.present?
      tell_other_hosts(event, user, actor: actor, change: 'added')
    end

    def host_removed(event, user, actor:)
      EventHostMailer.removed(user, event, actor: actor).deliver_later if user.email.present?
      tell_other_hosts(event, user, actor: actor, change: 'removed')
    end

    def event_cancelled(event, reason: nil)
      reason ||= event.cancellation_reason
      each_host(event) do |host|
        EventHostMailer.cancelled(host, event, reason: reason).deliver_later
      end
    end

    def event_postponed(event)
      each_host(event) do |host|
        EventHostMailer.postponed(host, event, until_time: event.postponed_until,
                                               reason: event.cancellation_reason).deliver_later
      end
      each_open_occurrence(event) { |occurrence| RsvpLifecycle.notify_changed!(occurrence, 'postponed') }
    end

    def event_rescheduled(event, previous_start:, previous_duration:)
      each_host(event) do |host|
        EventHostMailer.rescheduled(host, event, previous_start: previous_start,
                                                 previous_duration: previous_duration).deliver_later
      end
      return if event.saved_change_to_start_time?
      return unless event.saved_change_to_duration?

      # A longer or shorter event does not move occurs_at, so the per-date
      # time update never runs. Tell anyone still planning to be there.
      each_open_occurrence(event) { |occurrence| RsvpLifecycle.notify_changed!(occurrence, 'rescheduled') }
    end

    def occurrence_cancelled(occurrence, force: false)
      return if occurrence_hosts_silenced? && !force

      event = occurrence.event
      each_host(event) do |host|
        EventHostMailer.cancelled(host, event, occurrence: occurrence, reason: occurrence.cancellation_reason).deliver_later
      end
    end

    def occurrence_postponed(occurrence)
      return if occurrence_hosts_silenced?

      event = occurrence.event
      each_host(event) do |host|
        EventHostMailer.postponed(host, event, until_time: occurrence.postponed_until, occurrence: occurrence,
                                               reason: occurrence.cancellation_reason).deliver_later
      end
    end

    def occurrence_rescheduled(occurrence, previous_start:, previous_duration: nil)
      return if occurrence_hosts_silenced?

      event = occurrence.event
      each_host(event) do |host|
        EventHostMailer.rescheduled(host, event, occurrence: occurrence, previous_start: previous_start,
                                                 previous_duration: previous_duration).deliver_later
      end
    end

    def occurrence_relocated(occurrence)
      return if occurrence_hosts_silenced?

      event = occurrence.event
      each_host(event) do |host|
        EventHostMailer.relocated(host, event, occurrence: occurrence, location: occurrence.relocated_to,
                                               reason: occurrence.cancellation_reason).deliver_later
      end
    end

    def event_reactivated(event)
      each_host(event) do |host|
        EventHostMailer.reactivated(host, event).deliver_later
      end
      event.occurrences.not_yet_ended.where(status: EventOccurrence::LISTABLE_STATUSES).find_each do |occurrence|
        notify_previous_rsvps(occurrence)
      end
    end

    def occurrence_reactivated(occurrence)
      unless occurrence_hosts_silenced?
        event = occurrence.event
        each_host(event) do |host|
          EventHostMailer.reactivated(host, event, occurrence: occurrence).deliver_later
        end
      end
      notify_previous_rsvps(occurrence)
    end

    def event_venue_changed(event, previous_name:, current_name:)
      each_host(event) do |host|
        EventHostMailer.venue_changed(host, event, previous_name: previous_name, current_name: current_name).deliver_later
      end
      inheriting = event.occurrences.not_yet_ended.where(location_id: nil)
      inheriting.find_each { |occurrence| notify_venue(occurrence, previous_name) }
    end

    def occurrence_venue_changed(occurrence, previous_name:, current_name:)
      return if occurrence_hosts_silenced?

      event = occurrence.event
      each_host(event) do |host|
        EventHostMailer.venue_changed(host, event, previous_name: previous_name, current_name: current_name,
                                                   occurrence: occurrence).deliver_later
      end
      notify_venue(occurrence, previous_name)
    end

    private

    def each_host(event)
      event.event_hosts.includes(:user).find_each do |membership|
        user = membership.user
        next if user.nil? || user.email.blank?

        yield user
      end
    end

    def each_open_occurrence(event, &)
      event.occurrences.not_yet_ended.find_each(&)
    end

    def tell_other_hosts(event, member, actor:, change:)
      each_host(event) do |host|
        next if host.id == member.id

        EventHostMailer.roster_changed(host, event, actor: actor, member: member, change: change).deliver_later
      end
    end

    def notify_previous_rsvps(occurrence)
      occurrence.rsvps.where(status: 'cancelled', cancelled_via: 'occurrence_cancelled').find_each do |rsvp|
        RsvpNotifier.occurrence_changed(rsvp, 'reactivated')
      end
    end

    def notify_venue(occurrence, previous_name)
      occurrence.rsvps.where.not(status: 'cancelled').find_each do |rsvp|
        RsvpNotifier.venue_changed(rsvp, previous_name: previous_name)
      end
    end

    def occurrence_hosts_silenced?
      Thread.current[:silence_occurrence_host_mail]
    end
  end
end
