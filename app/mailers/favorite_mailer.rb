class FavoriteMailer < ApplicationMailer
  include CalendarAttachment

  CALENDAR_KINDS = %w[rescheduled relocated reactivated resumed venue].freeze

  def reminder(user, favorite, occurrence, kind:)
    @kind = kind
    attach_occurrences_calendar([occurrence])
    prepare(user, favorite, occurrence.event, occurrence, subject_for_reminder(occurrence, kind))
  end

  def schedule_changed(user, favorite, occurrence, kind, details = {})
    @kind = kind
    @change_sentence = schedule_change_sentence(kind)
    assign_change_details(details)
    target = calendar_occurrence(occurrence, kind)
    @previous_start ||= occurrence.occurs_at if kind == 'postponed' && target
    attach_occurrences_calendar([target]) if target && (kind == 'postponed' || CALENDAR_KINDS.include?(kind))
    prepare(user, favorite, occurrence.event, target || occurrence, schedule_subject(occurrence.event, kind))
  end

  def series_changed(user, favorite, event, kind, details = {})
    @kind = kind
    @change_sentence = schedule_change_sentence(kind)
    assign_change_details(details)
    @upcoming = event.occurrences.listable_upcoming.order(:occurs_at).limit(5)
    prepare(user, favorite, event, @upcoming.first, series_subject(event, kind))
  end

  def content_changed(user, favorite, event, changes:)
    @changes = changes
    @kinds = changes.map(&:kind).uniq
    occurrence = changes.filter_map(&:event_occurrence).first
    occurrence ||= event.occurrences.listable_upcoming.order(:occurs_at).first
    prepare(user, favorite, event, occurrence, "#{event.title} was updated")
  end

  def schedule_change_sentence(kind)
    case kind
    when 'cancelled' then 'has been cancelled'
    when 'postponed' then 'has been postponed'
    when 'relocated', 'venue' then 'has a new location'
    when 'reactivated', 'resumed' then 'is back on'
    else 'has a new time'
    end
  end

  def new_date(user, favorite, occurrence)
    attach_occurrences_calendar([occurrence])
    prepare(user, favorite, occurrence.event, occurrence, "A new date was added for #{occurrence.event.title}")
  end

  private

  def calendar_occurrence(occurrence, kind)
    return occurrence.replacement_occurrence if kind == 'postponed'
    return occurrence if CALENDAR_KINDS.include?(kind)

    nil
  end

  def assign_change_details(details)
    @previous_start = details[:previous_start]
    @previous_duration = details[:previous_duration]
    @previous_venue = details[:previous_venue]
    @reason = details[:reason]
  end

  def prepare(user, favorite, event, occurrence, subject)
    @user = user
    @favorite = favorite
    @event = event
    @occurrence = occurrence
    @site_config = SiteConfig.current
    @test_mode = EmailTestMode.test_mode?
    @page_url = occurrence ? event_occurrence_url(occurrence) : event_url(event)
    @unsubscribe_url = unsubscribe_favorite_url(favorite.generate_token_for(:unsubscribe))
    @preferences_url = edit_user_registration_url
    headers['List-Unsubscribe'] = "<#{@unsubscribe_url}>"
    headers['List-Unsubscribe-Post'] = 'List-Unsubscribe=One-Click'
    mail(to: EmailTestMode.recipient_for(user.email), subject: branded(subject))
  end

  def branded(text)
    "[#{@site_config&.organization_name || 'EventManager'}] #{text}"
  end

  def subject_for_reminder(occurrence, kind)
    when_label = kind == '7d' ? 'next week' : 'tomorrow'
    "Reminder: #{occurrence.event.title} is #{when_label}"
  end

  def schedule_subject(event, kind)
    case kind
    when 'cancelled' then "#{event.title} has been cancelled"
    when 'postponed' then "#{event.title} has been postponed"
    when 'relocated', 'venue' then "#{event.title} has a new location"
    when 'reactivated', 'resumed' then "#{event.title} is back on"
    else "#{event.title} has a new time"
    end
  end

  def series_subject(event, kind)
    case kind
    when 'cancelled' then "#{event.title} will not continue"
    when 'postponed' then "#{event.title} has been postponed"
    when 'venue' then "#{event.title} has a new location"
    when 'reactivated', 'resumed' then "#{event.title} is back on"
    else "The schedule for #{event.title} changed"
    end
  end
end
