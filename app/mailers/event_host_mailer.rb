class EventHostMailer < ApplicationMailer
  def added(user, event, actor:)
    @actor_label = person_label(actor)
    @notice = 'added'
    compose(user, event, "You're now a host of #{event.title}")
  end

  def removed(user, event, actor:)
    @actor_label = person_label(actor)
    @notice = 'removed'
    compose(user, event, "You're no longer a host of #{event.title}")
  end

  def cancelled(user, event, occurrence: nil, reason: nil)
    @occurrence = occurrence
    @reason = reason
    @notice = 'cancelled'
    compose(user, event, cancelled_subject(event, occurrence))
  end

  def postponed(user, event, until_time:, occurrence: nil, reason: nil)
    @occurrence = occurrence
    @until_time = until_time
    @reason = reason
    @notice = 'postponed'
    compose(user, event, postponed_subject(event, occurrence))
  end

  def rescheduled(user, event, occurrence: nil, previous_start: nil, previous_duration: nil)
    @occurrence = occurrence
    @previous_start = previous_start
    @previous_duration = previous_duration
    @notice = 'rescheduled'
    current_start = occurrence&.occurs_at || event.start_time
    current_duration = occurrence ? occurrence.duration : event.duration
    @start_changed = previous_start.present? && previous_start.to_i != current_start.to_i
    @duration_changed = previous_duration.present? && previous_duration.to_i != current_duration.to_i
    @schedule_only = occurrence.nil? && !@start_changed && !@duration_changed
    compose(user, event, rescheduled_subject(event, occurrence))
  end

  def relocated(user, event, occurrence:, location:, reason: nil)
    @occurrence = occurrence
    @location = location
    @reason = reason
    @notice = 'relocated'
    compose(user, event, "#{event.title} on #{short_date(occurrence.occurs_at)} has a new location")
  end

  private

  def compose(user, event, subject)
    @user = user
    @event = event
    @site_config = SiteConfig.current
    @test_mode = EmailTestMode.test_mode?
    @url = @occurrence ? event_occurrence_url(@occurrence) : event_url(event)
    mail(to: EmailTestMode.recipient_for(user.email), subject: subject_for(subject), template_name: 'notice')
  end

  def cancelled_subject(event, occurrence)
    return "#{event.title} was cancelled" if occurrence.blank?

    "#{event.title} on #{short_date(occurrence.occurs_at)} was cancelled"
  end

  def postponed_subject(event, occurrence)
    return "#{event.title} was postponed" if occurrence.blank?

    "#{event.title} on #{short_date(occurrence.occurs_at)} was postponed"
  end

  def rescheduled_subject(event, occurrence)
    return "#{event.title} has a new schedule" if @schedule_only
    return "#{event.title} on #{short_date(occurrence.occurs_at)} has a new time" if occurrence

    "#{event.title} has a new time"
  end

  def subject_for(text)
    "[#{@site_config&.organization_name || 'EventManager'}] #{text}"
  end

  def short_date(time)
    time.in_time_zone.strftime('%b %-d')
  end

  def person_label(user)
    return if user.blank?

    user.name.presence || user.username.presence
  end
end
