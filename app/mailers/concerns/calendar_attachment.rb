module CalendarAttachment
  extend ActiveSupport::Concern

  private

  def attach_occurrences_calendar(occurrences)
    rows = Array(occurrences).compact
    return if rows.empty?

    config = SiteConfig.current
    builder = IcalBuilder.new(host: calendar_feed_host(config),
                              organization_name: config&.organization_name,
                              name: rows.first.event.title)
    rows.each { |occurrence| builder.add_occurrence(occurrence, page_url: event_occurrence_url(occurrence)) }
    attachments['event.ics'] = { mime_type: 'text/calendar', content: builder.to_ical }
    @calendar_attached = true
  end

  def calendar_feed_host(config)
    url = config&.website_url
    return 'rsvp' if url.blank?

    URI.parse(url).host.presence || 'rsvp'
  rescue URI::InvalidURIError
    'rsvp'
  end
end
