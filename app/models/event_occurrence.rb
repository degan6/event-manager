class EventOccurrence < ApplicationRecord # rubocop:disable Metrics/ClassLength
  include SoftDeletable
  include OccurrenceRsvp

  belongs_to :event, counter_cache: true
  belongs_to :location, optional: true
  belongs_to :event_image, optional: true
  belongs_to :postponed_to, class_name: 'EventOccurrence', optional: true, inverse_of: :postponed_from
  has_one :postponed_from, class_name: 'EventOccurrence', foreign_key: :postponed_to_id,
                           inverse_of: :postponed_to, dependent: :nullify
  has_many :reminder_postings, dependent: :destroy
  has_many :rsvps, dependent: :destroy

  # Slugs are stable identifiers; only generate on create.
  before_validation :generate_slug, on: :create
  before_validation :normalize_custom_description_fields
  before_create :assign_pool_image, unless: :event_image_id?

  validates :occurs_at, presence: true
  validates :status, inclusion: { in: %w[active postponed cancelled relocated] }
  validates :slug, presence: true, uniqueness: true
  validates :relocated_to, presence: true, if: -> { status == 'relocated' }
  validates :capacity_override, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # Allow finding by slug or ID
  def self.friendly_find(param)
    find_by(slug: param) || find(param)
  end

  def to_param
    slug
  end

  scope :active, -> { where(status: 'active') }
  scope :postponed, -> { where(status: 'postponed') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :relocated, -> { where(status: 'relocated') }
  scope :upcoming, -> { where('occurs_at >= ?', Time.current).order(:occurs_at) }
  scope :past, -> { where('occurs_at < ?', Time.current).order(occurs_at: :desc) }

  # Occurrences that still belong in public listings. Relocated ones stay
  # listed so a permanently relocated event remains discoverable.
  LISTABLE_STATUSES = %w[active relocated].freeze
  # Occurrence statuses that can be linked as the live target of a postponement.
  REPLACEMENT_STATUSES = LISTABLE_STATUSES.freeze
  scope :listable_upcoming, lambda { |at = Time.current|
    where(status: LISTABLE_STATUSES).where(occurs_at: at..)
  }

  # Collapses the current scope to one row per event: whichever of its
  # occurrences comes first. Lets callers avoid loading every future occurrence
  # just to show the next one.
  scope :first_per_event, lambda {
    select('DISTINCT ON (event_occurrences.event_id) event_occurrences.*')
      .reorder(:event_id, :occurs_at)
  }

  # Each event's earliest listable upcoming occurrence.
  scope :next_per_event, ->(at = Time.current) { listable_upcoming(at).first_per_event }

  # Occurrences that have started or will start, and have not yet ended (respects duration_override).
  END_TIME_SQL = <<~SQL.squish
    event_occurrences.occurs_at + (
      COALESCE(event_occurrences.duration_override, events.duration) * INTERVAL '1 minute'
    )
  SQL
  scope :not_yet_ended, lambda { |at = Time.current|
    joins(:event).where("#{END_TIME_SQL} > ?", at)
  }

  # Format the date/time for this occurrence
  def when_text
    date_str = occurs_at.strftime('%B %d, %Y')
    time_str = occurs_at.strftime('%I:%M %p')
    "on #{date_str} at #{time_str}"
  end

  # Substitute {{when}} placeholder with actual date/time
  def substitute_when_placeholder(message)
    return message if message.blank?

    message.gsub(/\{\{when\}\}/i, when_text)
  end

  # Default short reminder message (for Bluesky - limited characters)
  def reminder_short_default(_days_ahead = nil)
    substitute_when_placeholder(event.reminder_short_default)
  end

  # Default long reminder message (for Slack/Instagram - more detail allowed)
  def reminder_long_default(_days_ahead = nil)
    base = substitute_when_placeholder(event.reminder_long_default)
    duration_str = format_duration_text(duration)

    # Add occurrence-specific details
    details = "\n📅 #{occurs_at.strftime('%B %d, %Y')} at #{occurs_at.strftime('%I:%M %p')} (#{duration_str})"
    details += "\n📍 #{event_location.name}" if event_location.present?

    "#{base}#{details}"
  end

  # Get the effective 7-day short reminder (own or inherited from event, with {{when}} substituted)
  def effective_reminder_7d_short
    message = reminder_7d_short.presence || event.reminder_7d_short
    substitute_when_placeholder(message)
  end

  # Get the effective 1-day short reminder (own or inherited from event, with {{when}} substituted)
  def effective_reminder_1d_short
    message = reminder_1d_short.presence || event.reminder_1d_short
    substitute_when_placeholder(message)
  end

  # Get the effective 7-day long reminder (own or inherited from event, with {{when}} substituted)
  def effective_reminder_7d_long
    message = reminder_7d_long.presence || event.reminder_7d_long
    substitute_when_placeholder(message)
  end

  # Get the effective 1-day long reminder (own or inherited from event, with {{when}} substituted)
  def effective_reminder_1d_long
    message = reminder_1d_long.presence || event.reminder_1d_long
    substitute_when_placeholder(message)
  end

  after_update :log_update
  after_update :propagate_rescheduled_time_to_predecessors!, if: :saved_change_to_occurs_at?
  after_update :notify_schedule_change
  after_save :log_banner_change

  attr_accessor :current_user_for_journal

  # Get the actual description (custom or inherited from event)
  def description
    custom_description.presence || event.description
  end

  # Formatted description for this date. A plain-text-only override hides the
  # event HTML so the page does not show formatting the plain text replaced.
  def description_html
    return custom_description_html if custom_description_html.present?
    return if custom_description.present?

    event.description_html
  end

  def rendered_description_html
    description_html.presence
  end

  # Get the actual duration (override or inherited from event)
  def duration
    duration_override || event.duration
  end

  # Get the banner image (own or inherited from event)
  def banner
    (event_image || event.fallback_event_image || EventImage.new).image
  end

  def banner_image
    banner
  end

  def custom_banner?
    custom_event_image?
  end

  # Get the location (own or inherited from event)
  def event_location
    location || event.location
  end

  # Latest scheduled time at the end of this occurrence's postponement chain.
  def rescheduled_time
    visited = Set.new
    current = self

    loop do
      if current.postponed_to_id.present? && current.postponed_to.present?
        break if visited.include?(current.id)

        visited.add(current.id)
        current = current.postponed_to
      else
        return current.postponed_until if current.status == 'postponed' && current.postponed_until.present?

        return current.occurs_at
      end
    end

    current.occurs_at
  end

  # Live replacement at the tail of a postponement chain (linked or legacy lookup).
  def replacement_occurrence
    return nil unless status == 'postponed'

    return listable_replacement(linked_replacement_tail) if postponed_to_id.present?

    listable_replacement(legacy_replacement_occurrence)
  end

  # Walk backward through postponement links and sync postponed_until on predecessors.
  def propagate_rescheduled_time_to_predecessors!
    latest = rescheduled_time
    visited = Set.new
    predecessor = postponed_from

    while predecessor
      break if visited.include?(predecessor.id)

      visited.add(predecessor.id)

      unless times_equal?(predecessor.postponed_until, latest)
        predecessor.current_user_for_journal = current_user_for_journal
        predecessor.update!(postponed_until: latest)
      end

      predecessor = predecessor.postponed_from
    end
  end

  # Mark occurrence as postponed
  def postpone!(until_date, reason = nil, user = nil)
    self.current_user_for_journal = user if user

    Rails.logger.info "Postponing occurrence ##{id} from #{occurs_at} to #{until_date}"

    success = false
    transaction do
      # A banner assigned to this occurrence follows it to the new date.
      new_occurrence = event.occurrences.create!(
        occurs_at: until_date,
        status: 'active',
        **(custom_event_image? ? { event_image: event_image, custom_event_image: true } : {})
      )

      unless update(status: 'postponed', postponed_until: until_date, cancellation_reason: reason,
                    postponed_to: new_occurrence)
        Rails.logger.error "Failed to mark occurrence ##{id} as postponed: #{errors.full_messages.join(', ')}"
        raise ActiveRecord::Rollback
      end

      Rails.logger.info "Successfully marked occurrence ##{id} as postponed"
      Rails.logger.info "✓ Created new active occurrence ##{new_occurrence.id} at #{until_date} for event ##{event.id}"

      new_occurrence.current_user_for_journal = current_user_for_journal
      new_occurrence.propagate_rescheduled_time_to_predecessors!

      log_status_change('postponed', reason, user) if user
      # Hosts are emailed from the status callback. Guests move with the new date.
      RsvpLifecycle.transfer!(self, new_occurrence)
      success = true
    end
    success
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "✗ Failed to postpone occurrence: #{e.message}"
    false
  end

  # Mark occurrence as cancelled
  def cancel!(reason = nil, user = nil)
    self.current_user_for_journal = user if user
    result = update(status: 'cancelled', cancellation_reason: reason)
    log_status_change('cancelled', reason, user) if result && user
    result
  end

  # Mark occurrence as relocated
  def relocate!(new_location, reason = nil, user = nil)
    self.current_user_for_journal = user if user
    result = update(status: 'relocated', relocated_to: new_location, cancellation_reason: reason)
    log_status_change('relocated', reason, user) if result && user
    result
  end

  # Reactivate occurrence
  def reactivate!(user = nil)
    self.current_user_for_journal = user if user
    result = update(status: 'active', postponed_until: nil, cancellation_reason: nil, relocated_to: nil,
                    postponed_to_id: nil)
    log_status_change('reactivated', nil, user) if result && user
    result
  end

  # Display name for this occurrence
  def name
    "#{event.title} - #{occurs_at.strftime('%B %d, %Y')}"
  end

  def soft_delete
    had_rsvps = rsvps.where.not(status: 'cancelled').exists?
    RsvpLifecycle.cancel_occurrence!(self)
    ScheduleNotifier.occurrence_cancelled(self, force: had_rsvps)
    super
  end

  private

  # Status and time edits from the occurrence form, the cancel and postpone
  # actions, and a direct update all come through here.
  def notify_schedule_change
    if saved_change_to_status?
      notify_status_change
    elsif saved_change_to_occurs_at? || saved_change_to_duration_override?
      notify_time_change
    end
    notify_venue_change if saved_change_to_location_id?
  end

  def notify_status_change
    case status
    when 'cancelled'
      RsvpLifecycle.cancel_occurrence!(self)
      ScheduleNotifier.occurrence_cancelled(self)
    when 'relocated'
      RsvpLifecycle.notify_changed!(self, 'relocated')
      ScheduleNotifier.occurrence_relocated(self)
    when 'postponed'
      ScheduleNotifier.occurrence_postponed(self)
      # postpone! moves RSVPs onto the new date and emails them from there.
      RsvpLifecycle.notify_changed!(self, 'postponed') if postponed_to_id.blank?
    when 'active'
      ScheduleNotifier.occurrence_reactivated(self) if saved_change_to_status.first == 'cancelled'
    end
  end

  def notify_venue_change
    previous = Location.find_by(id: saved_change_to_location_id.first)
    ScheduleNotifier.occurrence_venue_changed(self, previous_name: previous&.name, current_name: event_location&.name)
  end

  def notify_time_change
    RsvpLifecycle.notify_changed!(self, 'rescheduled')
    ScheduleNotifier.occurrence_rescheduled(
      self,
      previous_start: saved_change_to_occurs_at&.first || occurs_at,
      previous_duration: previous_duration_for_notice
    )
  end

  def previous_duration_for_notice
    return unless saved_change_to_duration_override

    saved_change_to_duration_override.first || event.duration
  end

  def normalize_custom_description_fields
    self.custom_description_html = EventDescription.sanitize(custom_description_html)
    return if custom_description.present? || custom_description_html.blank?

    self.custom_description = HtmlToPlainText.call(custom_description_html)
  end

  def linked_replacement_tail
    return nil if postponed_to.blank?

    visited = Set.new
    current = postponed_to

    while current.status == 'postponed' && current.postponed_to_id.present? && current.postponed_to.present?
      break if visited.include?(current.id)

      visited.add(current.id)
      current = current.postponed_to
    end

    current
  end

  def legacy_replacement_occurrence
    return nil if postponed_until.blank?

    event.occurrences.find_by(occurs_at: postponed_until, status: REPLACEMENT_STATUSES)
  end

  def listable_replacement(occurrence)
    return nil unless occurrence
    return nil unless REPLACEMENT_STATUSES.include?(occurrence.status)

    occurrence
  end

  def times_equal?(left, right)
    return true if left.blank? && right.blank?
    return false if left.blank? || right.blank?

    left.to_i == right.to_i
  end

  def format_duration_text(minutes)
    hours = minutes / 60
    mins = minutes % 60
    if hours.positive? && mins.positive?
      "#{hours}h #{mins}m"
    elsif hours.positive?
      "#{hours} hour#{'s' if hours > 1}"
    else
      "#{mins} minutes"
    end
  end

  def generate_slug
    return if slug.present?

    assign_unique_slug_from_occurs_at
  end

  def assign_unique_slug_from_occurs_at
    return if event.blank? || occurs_at.blank?

    event_slug = event.title.parameterize
    date_slug = occurs_at.strftime('%Y-%m-%d')
    base_slug = "#{event_slug}-#{date_slug}"
    new_slug = base_slug
    counter = 1

    conflict_scope = EventOccurrence.unscoped
    conflict_scope = conflict_scope.where.not(id: id) if persisted?

    # Check against ALL occurrences including soft-deleted ones to avoid conflicts
    while conflict_scope.exists?(slug: new_slug)
      new_slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = new_slug
  end

  def assign_pool_image
    selected = EventImageSelector.new(event).select
    self.event_image = selected if selected
  end

  def log_update
    return unless current_user_for_journal
    return unless saved_changes.any?

    tracked_changes = {}
    saved_changes.each do |key, (old_val, new_val)|
      next if %w[updated_at created_at].include?(key)

      tracked_changes[key] = { 'from' => old_val, 'to' => new_val }
    end

    return if tracked_changes.empty?

    EventJournal.log_occurrence_change(
      self,
      current_user_for_journal,
      'updated',
      tracked_changes
    )
  end

  def log_status_change(action, reason, user)
    return unless user

    changes_data = { 'status' => action }
    changes_data['reason'] = reason if reason.present?

    EventJournal.log_occurrence_change(
      self,
      user,
      action,
      changes_data
    )
  end

  def log_banner_change
    return unless current_user_for_journal
    return if new_record?
    return unless saved_change_to_event_image_id?
    return unless event_image&.image&.attached?

    EventJournal.log_occurrence_change(
      self,
      current_user_for_journal,
      'banner_added',
      {
        'banner_image' => {
          'filename' => event_image.image.filename.to_s,
          'size' => "#{(event_image.image.byte_size.to_f / 1024).round(2)} KB",
          'content_type' => event_image.image.content_type
        }
      }
    )
  end

end
