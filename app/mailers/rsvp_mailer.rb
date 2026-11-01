class RsvpMailer < ApplicationMailer
  include CalendarAttachment

  CALENDAR_KINDS = %w[rescheduled relocated reactivated venue resumed].freeze

  def confirm_email(rsvp)
    compose(rsvp, "Confirm your RSVP for #{rsvp.event_occurrence.event.title}")
  end

  def confirmed(rsvp)
    compose(rsvp, "You're confirmed for #{rsvp.event_occurrence.event.title}")
  end

  def waitlisted(rsvp)
    compose(rsvp, "You're on the wait list for #{rsvp.event_occurrence.event.title}")
  end

  def spot_open(rsvp)
    compose(rsvp, "A spot opened for #{rsvp.event_occurrence.event.title}")
  end

  def spot_held(rsvp)
    compose(rsvp, "A spot is held for you: #{rsvp.event_occurrence.event.title}")
  end

  def offer_reminder(rsvp)
    compose(rsvp, "Reminder: a spot is open for #{rsvp.event_occurrence.event.title}")
  end

  def reminder(rsvp, kind:, nag: false)
    @kind = kind
    @nag = nag
    label = reminder_label(kind)
    compose(rsvp, "Reminder: #{rsvp.event_occurrence.event.title} is #{label}")
  end

  def cancelled_by_host(rsvp)
    compose(rsvp, "Your RSVP was cancelled: #{rsvp.event_occurrence.event.title}")
  end

  def occurrence_changed(rsvp, kind:)
    @change_kind = kind
    @calendar_note = CALENDAR_KINDS.include?(kind)
    title = rsvp.event_occurrence.event.title
    subject = case kind
              when 'cancelled' then "#{title} has been cancelled"
              when 'postponed' then "#{title} has been postponed"
              when 'relocated' then "#{title} has moved"
              when 'reactivated' then "#{title} is happening again"
              when 'resumed' then "#{title} is back on"
              else "#{title} has changed"
              end
    compose(rsvp, subject)
  end

  def venue_changed(rsvp, previous_name:)
    @change_kind = 'venue'
    @previous_venue = previous_name
    @calendar_note = true
    title = rsvp.event_occurrence.event.title
    compose(rsvp, "#{title} has a new location", template_name: 'occurrence_changed')
  end

  def login_required(email, occurrence)
    @email = email
    @occurrence = occurrence
    @event = occurrence.event
    @site_config = SiteConfig.current
    @login_url = new_user_session_url
    @test_mode = EmailTestMode.test_mode?
    mail(to: EmailTestMode.recipient_for(email), subject: subject_for("Sign in to RSVP for #{@event.title}"))
  end

  private

  def compose(rsvp, subject, template_name: nil)
    @rsvp = rsvp
    @occurrence = rsvp.event_occurrence
    @event = @occurrence.event
    @site_config = SiteConfig.current
    @manage_url = manage_rsvp_url(rsvp.manage_token)
    @rsvp_again_url = event_occurrence_url(@occurrence) if @change_kind == 'reactivated'
    @current_venue = @occurrence.venue_name if @change_kind == 'venue'
    @test_mode = EmailTestMode.test_mode?
    attach_occurrences_calendar([@occurrence]) if action_name == 'confirmed' || @calendar_note
    delivery = { to: EmailTestMode.recipient_for(rsvp.email), subject: subject_for(subject) }
    delivery[:template_name] = template_name if template_name
    mail(delivery)
  end

  def reminder_label(kind)
    return 'today' if kind == 'day_of'
    return 'in 7 days' if kind == '7d'

    'in 1 day'
  end

  def subject_for(text)
    "[#{@site_config&.organization_name || 'EventManager'}] #{text}"
  end
end
