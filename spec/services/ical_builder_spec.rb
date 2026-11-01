require 'rails_helper'

RSpec.describe IcalBuilder do
  subject(:ical) { builder.add_occurrence(occurrence, **add_options).to_ical }

  # 2026-08-19 18:30 PDT is 2026-08-20 01:30 UTC. Emitting that UTC wall clock
  # without a "Z" suffix made clients read it as 1:30 AM local time, a day late.
  let(:summer_local) { Time.zone.parse('2026-08-19 18:30') }
  let(:winter_local) { Time.zone.parse('2026-01-14 18:30') }

  let(:event) do
    create(:event, title: 'Exploit Workshop', duration: 240, description: 'Weekly security meetup')
  end
  let(:occurrence) { create(:event_occurrence, event: event, occurs_at: summer_local) }

  let(:builder_options) { {} }
  let(:add_options) { {} }
  let(:builder) { described_class.new(host: 'events.example.org', **builder_options) }

  around { |example| Time.use_zone('America/Los_Angeles') { example.run } }

  # RFC 5545 folds lines longer than 75 octets; unfold so values can be matched whole.
  def unfold(document)
    document.gsub(/\r\n[ \t]/, '')
  end

  def property(document, name)
    unfold(document).lines.map(&:chomp).find { |line| line.start_with?("#{name}:", "#{name};") }
  end

  def value_of(document, name)
    property(document, name)&.split(':', 2)&.last
  end

  describe '.utc_date_time' do
    it 'suffixes the serialized value with Z' do
      expect(described_class.utc_date_time(summer_local).value_ical).to eq('20260820T013000Z')
    end

    it 'converts a daylight saving time to its UTC instant' do
      expect(described_class.utc_date_time(summer_local).value_ical).to start_with('20260820')
    end

    it 'converts a standard time to its UTC instant' do
      expect(described_class.utc_date_time(winter_local).value_ical).to eq('20260115T023000Z')
    end

    it 'accepts a time that is already in UTC' do
      expect(described_class.utc_date_time(summer_local.utc).value_ical).to eq('20260820T013000Z')
    end
  end

  describe '.ical_status' do
    it 'maps active to CONFIRMED' do
      expect(described_class.ical_status('active')).to eq('CONFIRMED')
    end

    it 'maps postponed to TENTATIVE' do
      expect(described_class.ical_status('postponed')).to eq('TENTATIVE')
    end

    it 'maps cancelled to CANCELLED' do
      expect(described_class.ical_status('cancelled')).to eq('CANCELLED')
    end

    it 'maps relocated to CONFIRMED' do
      expect(described_class.ical_status('relocated')).to eq('CONFIRMED')
    end

    it 'falls back to CONFIRMED for an unrecognized status' do
      expect(described_class.ical_status('something-else')).to eq('CONFIRMED')
    end

    it 'only ever returns a status RFC 5545 permits' do
      statuses = EventOccurrence.validators_on(:status)
                                .flat_map { |v| v.options[:in] || [] }
                                .map { |status| described_class.ical_status(status) }

      expect(statuses.uniq).to all(be_in(%w[TENTATIVE CONFIRMED CANCELLED]))
    end
  end

  describe '.uid_for' do
    it 'combines the occurrence id with the host' do
      expect(described_class.uid_for(occurrence, 'events.example.org'))
        .to eq("occurrence-#{occurrence.id}@events.example.org")
    end
  end

  describe 'DATE-TIME serialization' do
    it 'emits DTSTART as the UTC instant of the occurrence' do
      expect(property(ical, 'DTSTART')).to eq('DTSTART:20260820T013000Z')
    end

    it 'emits DTEND advanced by the event duration' do
      expect(property(ical, 'DTEND')).to eq('DTEND:20260820T053000Z')
    end

    it 'emits DTSTAMP in UTC' do
      expect(property(ical, 'DTSTAMP')).to match(/\ADTSTAMP:\d{8}T\d{6}Z\z/)
    end

    it 'never emits a floating DATE-TIME' do
      date_times = unfold(ical).lines.map(&:chomp).grep(/\A(DTSTART|DTEND|DTSTAMP)[:;]/)

      expect(date_times).to all(end_with('Z'))
    end

    it 'does not emit a TZID parameter' do
      expect(ical).not_to include('TZID')
    end

    it 'honours a duration override when computing DTEND' do
      occurrence.update!(duration_override: 30)

      expect(property(ical, 'DTEND')).to eq('DTEND:20260820T020000Z')
    end

    it 'converts a standard-time occurrence to the correct UTC instant' do
      occurrence.update!(occurs_at: winter_local)

      expect(property(ical, 'DTSTART')).to eq('DTSTART:20260115T023000Z')
    end

    it 'serializes the same instant regardless of the application time zone' do
      occurrence # create while the application zone is Pacific

      starts = ['America/Los_Angeles', 'America/New_York', 'UTC', 'Australia/Sydney'].map do |zone|
        Time.use_zone(zone) do
          property(described_class.new(host: 'events.example.org').add_occurrence(occurrence).to_ical, 'DTSTART')
        end
      end

      expect(starts.uniq).to eq(['DTSTART:20260820T013000Z'])
    end
  end

  describe 'round trip through a parser' do
    let(:parsed) { Icalendar::Calendar.parse(ical).first.events.first }

    it 'reads back the instant the occurrence starts' do
      expect(parsed.dtstart.to_time.to_i).to eq(occurrence.occurs_at.to_i)
    end

    it 'reads back the instant the occurrence ends' do
      expected = (occurrence.occurs_at + occurrence.duration.minutes).to_i

      expect(parsed.dtend.to_time.to_i).to eq(expected)
    end

    it 'reads back 6:30 PM Pacific rather than a shifted wall clock' do
      expect(parsed.dtstart.to_time.in_time_zone('America/Los_Angeles').strftime('%Y-%m-%d %H:%M'))
        .to eq('2026-08-19 18:30')
    end
  end

  describe 'STATUS' do
    it 'marks an active occurrence CONFIRMED' do
      expect(property(ical, 'STATUS')).to eq('STATUS:CONFIRMED')
    end

    it 'marks a cancelled occurrence CANCELLED' do
      occurrence.update!(status: 'cancelled', cancellation_reason: 'Snow')

      expect(property(ical, 'STATUS')).to eq('STATUS:CANCELLED')
    end

    it 'marks a postponed occurrence TENTATIVE' do
      occurrence.update!(status: 'postponed', postponed_until: winter_local)

      expect(property(ical, 'STATUS')).to eq('STATUS:TENTATIVE')
    end

    it 'marks a relocated occurrence CONFIRMED' do
      occurrence.update!(status: 'relocated', relocated_to: 'Section 3')

      expect(property(ical, 'STATUS')).to eq('STATUS:CONFIRMED')
    end
  end

  describe 'DESCRIPTION' do
    it 'includes the occurrence description' do
      expect(unfold(ical)).to include('Weekly security meetup')
    end

    it 'keeps HTML tags out of the plain description' do
      event.update!(description: 'Hello there', description_html: '<p>Hello <strong>there</strong></p>')

      expect(value_of(ical, 'DESCRIPTION')).to include('Hello there')
      expect(value_of(ical, 'DESCRIPTION')).not_to include('<')
    end

    it 'adds an HTML alternative when the description has formatting' do
      event.update!(description: 'Hello there', description_html: '<p>Hello <strong>there</strong></p>')

      document = unfold(ical)
      expect(document).to include('X-ALT-DESC;FMTTYPE=text/html')
      expect(document).to include('<strong>there</strong>')
    end

    it 'includes status notes and links in the HTML alternative' do
      event.update!(
        description: 'Hello there',
        description_html: '<p>Hello <strong>there</strong></p>',
        more_info_url: 'https://example.com/info'
      )
      occurrence.update!(status: 'cancelled', cancellation_reason: 'Snow')
      document = described_class.new(host: 'events.example.org')
                                .add_occurrence(occurrence, page_url: 'https://example.org/o/1')
                                .to_ical

      html = value_of(unfold(document), 'X-ALT-DESC')
      expect(html).to include('<strong>there</strong>')
      expect(html).to include('Cancelled: Snow')
      expect(html).to include('https://example.com/info')
      expect(html).to include('https://example.org/o/1')
    end

    it 'omits the HTML alternative when there is no formatted description' do
      expect(unfold(ical)).not_to include('X-ALT-DESC')
    end

    it 'prefers a custom occurrence description over the event description' do
      occurrence.update!(custom_description: 'Bring a laptop')

      expect(unfold(ical)).to include('Bring a laptop')
    end

    it 'includes the more info URL when the event has one' do
      event.update!(more_info_url: 'https://example.com/info')

      expect(unfold(ical)).to include('More info: https://example.com/info')
    end

    it 'omits the more info line when the event has none' do
      expect(unfold(ical)).not_to include('More info:')
    end

    it 'includes the event page link when a page URL is given' do
      expect(described_class.description_for(occurrence, page_url: 'https://example.org/o/1'))
        .to include('Event page: https://example.org/o/1')
    end

    it 'omits the event page line when no page URL is given' do
      expect(described_class.description_for(occurrence)).not_to include('Event page:')
    end

    it 'notes the cancellation reason' do
      occurrence.update!(status: 'cancelled', cancellation_reason: 'Snow')

      expect(described_class.description_for(occurrence)).to include('Cancelled: Snow')
    end

    it 'notes the rescheduled date for a postponed occurrence' do
      occurrence.update!(status: 'postponed', postponed_until: winter_local)

      expect(described_class.description_for(occurrence)).to include('Rescheduled to: January 14, 2026 at 06:30 PM')
    end

    it 'notes the new location for a relocated occurrence' do
      occurrence.update!(status: 'relocated', relocated_to: 'Section 3')

      expect(described_class.description_for(occurrence)).to include('New Location: Section 3')
    end

    it 'does not leave a blank leading section when there is no description' do
      event.update!(description: nil)
      occurrence.update!(custom_description: nil, status: 'cancelled', cancellation_reason: 'Snow')

      expect(described_class.description_for(occurrence)).to eq('Cancelled: Snow')
    end
  end

  describe 'VEVENT identity and detail' do
    it 'uses the event title as the summary' do
      expect(property(ical, 'SUMMARY')).to eq('SUMMARY:Exploit Workshop')
    end

    it 'derives the UID from the occurrence and the request host' do
      expect(property(ical, 'UID')).to eq("UID:occurrence-#{occurrence.id}@events.example.org")
    end

    it 'keeps the UID stable across rebuilds so subscribers do not duplicate events' do
      first = value_of(ical, 'UID')
      second = value_of(described_class.new(host: 'events.example.org').add_occurrence(occurrence).to_ical, 'UID')

      expect(second).to eq(first)
    end

    it 'includes the location when the occurrence has one' do
      occurrence.update!(location: create(:location, name: 'Section 2'))

      expect(property(ical, 'LOCATION')).to eq('LOCATION:Section 2')
    end

    it 'uses the relocated place as the calendar location' do
      occurrence.update!(status: 'relocated', relocated_to: 'Section 3')

      expect(property(ical, 'LOCATION')).to eq('LOCATION:Section 3')
    end

    it 'omits the location when neither occurrence nor event has one' do
      expect(property(ical, 'LOCATION')).to be_nil
    end

    it 'sets URL to the page URL when given' do
      expect(value_of(ical_with(page_url: 'https://example.org/o/1'), 'URL')).to eq('https://example.org/o/1')
    end

    it 'omits URL when no page URL is given' do
      expect(property(ical, 'URL')).to be_nil
    end

    it 'sets the organizer when given' do
      expect(value_of(ical_with(organizer: 'Hosts: Ada'), 'ORGANIZER')).to eq('Hosts: Ada')
    end

    it 'omits the organizer when none is given' do
      expect(property(ical, 'ORGANIZER')).to be_nil
    end

    def ical_with(**)
      described_class.new(host: 'events.example.org').add_occurrence(occurrence, **).to_ical
    end
  end

  describe 'VCALENDAR properties' do
    it 'builds a PRODID from the organization name' do
      builder = described_class.new(host: 'events.example.org', organization_name: 'CTRL-H')

      expect(property(builder.to_ical, 'PRODID')).to eq('PRODID:-//CTRL-H//Calendar//EN')
    end

    it 'falls back to a default PRODID when there is no organization name' do
      expect(property(ical, 'PRODID')).to eq('PRODID:-//EventManager//Calendar//EN')
    end

    it 'advertises the calendar name when one is given' do
      builder = described_class.new(host: 'events.example.org', name: 'CTRL-H Events')

      expect(property(builder.to_ical, 'X-WR-CALNAME')).to eq('X-WR-CALNAME:CTRL-H Events')
    end

    it 'omits the calendar name when none is given' do
      expect(property(ical, 'X-WR-CALNAME')).to be_nil
    end

    it 'advertises the application time zone for display purposes' do
      expect(property(ical, 'X-WR-TIMEZONE')).to eq('X-WR-TIMEZONE:America/Los_Angeles')
    end

    it 'declares METHOD:PUBLISH for feeds' do
      builder = described_class.new(host: 'events.example.org', publish: true)

      expect(property(builder.to_ical, 'METHOD')).to eq('METHOD:PUBLISH')
    end

    it 'omits METHOD for a single downloaded event' do
      expect(property(ical, 'METHOD')).to be_nil
    end

    it 'produces a well formed document with no occurrences' do
      document = described_class.new(host: 'events.example.org').to_ical

      expect(document).to include('BEGIN:VCALENDAR').and include('END:VCALENDAR')
      expect(document).not_to include('BEGIN:VEVENT')
    end
  end
end
