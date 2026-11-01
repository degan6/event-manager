# Builds RFC 5545 iCalendar documents for event occurrences.
#
# Every DATE-TIME is emitted as a UTC instant with a trailing "Z". The icalendar
# gem infers nothing from the Ruby object it is handed: it appends "Z" only when
# given an explicit 'UTC' tzid parameter, and otherwise emits a floating time
# that clients resolve against the viewer's own time zone.
class IcalBuilder
  UTC_TZID = { 'tzid' => 'UTC' }.freeze

  # RFC 5545 3.8.1.11 permits only TENTATIVE, CONFIRMED and CANCELLED, so the
  # application's own occurrence statuses have to be mapped onto them.
  ICAL_STATUSES = {
    'active' => 'CONFIRMED',
    'postponed' => 'TENTATIVE',
    'cancelled' => 'CANCELLED',
    'relocated' => 'CONFIRMED'
  }.freeze

  DEFAULT_STATUS = 'CONFIRMED'.freeze
  DEFAULT_ORGANIZATION = 'EventManager'.freeze
  NOTE_TIME_FORMAT = '%B %d, %Y at %I:%M %p'.freeze

  class << self
    def utc_date_time(time)
      Icalendar::Values::DateTime.new(time.utc, UTC_TZID)
    end

    def ical_status(status)
      ICAL_STATUSES.fetch(status, DEFAULT_STATUS)
    end

    def uid_for(occurrence, host)
      "occurrence-#{occurrence.id}@#{host}"
    end

    # Shared description text for every calendar target: iCal feeds, the single
    # occurrence download, and the Google/Outlook/Yahoo "add to calendar" links.
    def description_for(occurrence, page_url: nil)
      parts = [occurrence.description, *status_notes(occurrence)]
      parts << "More info: #{occurrence.event.more_info_url}" if occurrence.event.more_info_url.present?
      parts << "Event page: #{page_url}" if page_url.present?
      parts.compact_blank.join("\n\n")
    end

    # Same notes as the plain description, so a client that shows the HTML
    # alternative still includes cancellations, the more-info link, and the
    # event page.
    def html_description_for(occurrence, page_url: nil)
      body = EventDescription.for_display(occurrence.rendered_description_html)
      return if body.blank?

      parts = [String.new(body.to_s)]
      status_notes(occurrence).each { |note| parts << html_paragraph(note) }
      parts << html_link_paragraph('More info', occurrence.event.more_info_url)
      parts << html_link_paragraph('Event page', page_url)
      String.new(parts.compact.join)
    end

    private

    def html_paragraph(text)
      "<p>#{ERB::Util.html_escape(text)}</p>"
    end

    def html_link_paragraph(label, url)
      return if url.blank?

      escaped = ERB::Util.html_escape(url)
      "<p>#{ERB::Util.html_escape(label)}: <a href=\"#{escaped}\">#{escaped}</a></p>"
    end

    def status_notes(occurrence)
      [cancellation_note(occurrence), reschedule_note(occurrence), relocation_note(occurrence)].compact
    end

    def cancellation_note(occurrence)
      return nil if occurrence.cancellation_reason.blank?

      "#{occurrence.status.titleize}: #{occurrence.cancellation_reason}"
    end

    def reschedule_note(occurrence)
      return nil unless occurrence.status == 'postponed' && occurrence.postponed_until

      "Rescheduled to: #{occurrence.postponed_until.strftime(NOTE_TIME_FORMAT)}"
    end

    def relocation_note(occurrence)
      return nil unless occurrence.status == 'relocated' && occurrence.relocated_to.present?

      "New Location: #{occurrence.relocated_to}"
    end
  end

  def initialize(host:, organization_name: nil, name: nil, publish: false)
    @host = host
    @publish = publish
    @calendar = Icalendar::Calendar.new
    @calendar.prodid = "-//#{organization_name.presence || DEFAULT_ORGANIZATION}//Calendar//EN"
    @calendar.append_custom_property('X-WR-CALNAME', name) if name.present?
    @calendar.append_custom_property('X-WR-TIMEZONE', Time.zone.tzinfo.name)
  end

  def add_occurrence(occurrence, page_url: nil, organizer: nil)
    ends_at = occurrence.occurs_at + occurrence.duration.minutes

    @calendar.event do |e|
      e.dtstart = self.class.utc_date_time(occurrence.occurs_at)
      e.dtend = self.class.utc_date_time(ends_at)
      e.dtstamp = self.class.utc_date_time(occurrence.updated_at)
      e.uid = self.class.uid_for(occurrence, @host)
      e.summary = occurrence.event.title
      e.status = self.class.ical_status(occurrence.status)
      e.description = self.class.description_for(occurrence, page_url: page_url)
      html = self.class.html_description_for(occurrence, page_url: page_url)
      if html.present?
        alt = Icalendar::Values::Text.new(html, { 'fmttype' => 'text/html' })
        e.append_custom_property('x-alt-desc', alt)
      end
      place = if occurrence.status == 'relocated' && occurrence.relocated_to.present?
                occurrence.relocated_to
              elsif occurrence.event_location
                occurrence.event_location.name
              end
      e.location = place if place.present?
      e.url = page_url if page_url.present?
      e.organizer = organizer if organizer.present?
    end

    self
  end

  def to_ical
    @calendar.publish if @publish
    @calendar.to_ical
  end
end
