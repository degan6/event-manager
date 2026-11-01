class RsvpMailer < ApplicationMailer
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
    title = rsvp.event_occurrence.event.title
    subject = case kind
              when 'cancelled' then "#{title} has been cancelled"
              when 'postponed' then "#{title} has been postponed"
              when 'relocated' then "#{title} has moved"
              else "#{title} has changed"
              end
    compose(rsvp, subject)
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

  def compose(rsvp, subject)
    @rsvp = rsvp
    @occurrence = rsvp.event_occurrence
    @event = @occurrence.event
    @site_config = SiteConfig.current
    @manage_url = manage_rsvp_url(rsvp.manage_token)
    @test_mode = EmailTestMode.test_mode?
    attach_calendar if action_name == 'confirmed'
    mail(to: EmailTestMode.recipient_for(rsvp.email), subject: subject_for(subject))
  end

  def reminder_label(kind)
    return 'today' if kind == 'day_of'
    return 'in 7 days' if kind == '7d'

    'in 1 day'
  end

  def subject_for(text)
    "[#{@site_config&.organization_name || 'EventManager'}] #{text}"
  end

  def attach_calendar
    ical = IcalBuilder.new(host: calendar_host, organization_name: @site_config&.organization_name, name: @event.title)
                      .add_occurrence(@occurrence, page_url: event_occurrence_url(@occurrence))
                      .to_ical
    attachments['event.ics'] = { mime_type: 'text/calendar', content: ical }
  end

  def calendar_host
    url = @site_config&.website_url
    return 'rsvp' if url.blank?

    URI.parse(url).host.presence || 'rsvp'
  rescue URI::InvalidURIError
    'rsvp'
  end
end
