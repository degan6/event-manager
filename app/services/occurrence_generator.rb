# frozen_string_literal: true

# Service object for generating and managing event occurrences
# Extracted from Event model to centralize IceCube scheduling and DST handling logic
class OccurrenceGenerator
  attr_reader :event

  def initialize(event)
    @event = event
  end

  # Generate future occurrences based on recurrence rules
  def generate(limit: nil)
    return if event.permanently_cancelled? || event.permanently_relocated?

    limit ||= event.max_occurrences || 5
    occurrence_status = event.default_to_cancelled? ? 'cancelled' : 'active'

    if event.recurrence_type == 'once'
      occ = find_or_create_occurrence_by_date(event.start_time, occurrence_status)
      save_occurrence(occ)
    elsif event.recurrence_rule.present?
      schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
      future_dates = schedule.occurrences_between(
        Time.current.in_time_zone(Time.zone),
        1.year.from_now.in_time_zone(Time.zone)
      ).first(limit)

      future_dates.each do |date|
        occ = find_or_create_occurrence_by_date(date, occurrence_status)
        save_occurrence(occ)
      end
    end
  end

  # Regenerate occurrences (useful after recurrence rule changes)
  # Updates occurrences in place to preserve URLs/slugs
  def regenerate_future!
    return if event.permanently_cancelled? || event.permanently_relocated?

    scheduled_dates = future_scheduled_dates
    existing_future = event.occurrences.not_yet_ended
    existing_by_date = existing_future
                       .group_by { |occ| occ.occurs_at.in_time_zone(Time.zone).to_date }
                       .transform_values { |occurrences| occurrences.min_by(&:id) }
    scheduled_date_set = scheduled_dates.to_set { |d| d.in_time_zone(Time.zone).to_date }
    event.occurrences.not_yet_ended.each do |occ|
      next unless occ.occurs_at <= Time.current

      scheduled_date_set.add(occ.occurs_at.in_time_zone(Time.zone).to_date)
    end

    occurrence_status = event.default_to_cancelled? ? 'cancelled' : 'active'
    created = []
    scheduled_dates.each do |scheduled_time|
      scheduled_date = scheduled_time.in_time_zone(Time.zone).to_date
      existing = existing_by_date[scheduled_date]

      if existing
        # Preserve manually managed occurrences (cancelled/postponed/relocated)
        # and only normalize wall-clock time for active scheduled occurrences.
        update_occurrence_time_if_needed(existing, scheduled_time) if existing.status == 'active'
      else
        created << save_occurrence(
          event.occurrences.build(occurs_at: canonicalize_time(scheduled_time), status: occurrence_status)
        )
      end
    end

    removed = unscheduled_active(existing_by_date, scheduled_date_set)
    # A one-time event moved to another day used to drop the old date and
    # cancel its RSVPs. Keep those RSVPs on the new date and tell people it moved.
    rehome_replaced_once(removed, created)
    removed.each { |occ| discard_from_schedule(occ) }
  end

  # Get future scheduled dates based on recurrence rule
  def future_scheduled_dates
    limit = event.max_occurrences || 5

    if event.recurrence_type == 'once'
      end_time = event.start_time + event.duration.minutes
      end_time > Time.current ? [event.start_time] : []
    elsif event.recurrence_rule.present?
      schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
      schedule.occurrences_between(
        Time.current.in_time_zone(Time.zone),
        1.year.from_now.in_time_zone(Time.zone)
      ).first(limit)
    else
      []
    end
  end

  # Find existing occurrence by date (ignoring time) or create new one
  # If existing occurrence has wrong time, update it to the correct time
  def find_or_create_occurrence_by_date(scheduled_time, default_status)
    canonical_time = canonicalize_time(scheduled_time)
    scheduled_date = canonical_time.in_time_zone(Time.zone).to_date
    existing = occurrence_for_local_date(scheduled_date)

    if existing
      existing.occurs_at = canonical_time if existing.occurs_at.utc != canonical_time.utc
      existing
    else
      event.occurrences.build(occurs_at: canonical_time, status: default_status)
    end
  end

  # Update an occurrence's time if it doesn't match the scheduled time
  def update_occurrence_time_if_needed(occurrence, scheduled_time)
    canonical_time = canonicalize_time(scheduled_time)
    previous = occurrence.occurs_at
    return if previous.utc == canonical_time.utc

    occurrence.update_column(:occurs_at, canonical_time) # rubocop:disable Rails/SkipsModelValidations
    FavoriteReminderDelivery.clear_for(occurrence)
    occurrence.reload
    occurrence.propagate_rescheduled_time_to_predecessors!
    # update_column skips the occurrence callback that normally sends these.
    RsvpLifecycle.notify_changed!(occurrence, 'rescheduled')
    ScheduleNotifier.occurrence_rescheduled(occurrence, previous_start: previous)
  end

  private

  def unscheduled_active(existing_by_date, scheduled_date_set)
    existing_by_date.filter_map do |date, occ|
      next if scheduled_date_set.include?(date)
      next unless occ.status == 'active'
      next if manually_rescheduled?(occ)
      next if occ.occurs_at <= Time.current && (occ.occurs_at + occ.duration.minutes) > Time.current

      occ
    end
  end

  def rehome_replaced_once(removed, created)
    return unless event.recurrence_type == 'once'
    return unless removed.one? && created.one?
    return unless created.first.status == 'active'

    RsvpLifecycle.transfer!(removed.first, created.first)
    FavoriteService.transfer!(removed.first, created.first)
  end

  def discard_from_schedule(occurrence)
    remember_dropped_favorites(occurrence)
    if occurrence.cancellation_reason.blank? && occurrence.rsvps.where.not(status: 'cancelled').exists?
      reason = 'This date was removed from the schedule'
      occurrence.update_column(:cancellation_reason, reason) # rubocop:disable Rails/SkipsModelValidations
    end
    occurrence.destroy
  end

  def remember_dropped_favorites(occurrence)
    user_ids = occurrence.favorites.pluck(:user_id)
    return if user_ids.empty?

    event.dropped_favorite_user_ids = Array(event.dropped_favorite_user_ids) | user_ids
  end

  def save_occurrence(occurrence)
    return occurrence unless occurrence.changed? || occurrence.new_record?

    occurrence.save!
    note_exclusive_conflict(occurrence)
    occurrence
  end

  # Background generation can't ask anyone to pick another time, so an overlap
  # with an exclusive event is logged and left for the hosts to see on the
  # occurrence page.
  def note_exclusive_conflict(occurrence)
    return unless occurrence.status == 'active'

    blocks = ScheduleConflictChecker.for_occurrence(occurrence).blocks
    return if blocks.empty?

    names = blocks.map { |conflict| conflict.event.title }.uniq.join(', ')
    Rails.logger.warn(
      "Occurrence #{occurrence.id} (#{event.title} at #{occurrence.occurs_at}) overlaps exclusive event(s): #{names}"
    )
  end

  # Canonicalize to the schedule's intended local wall-clock time for the date.
  # This keeps local times stable across DST boundaries regardless of offsets
  # returned by IceCube for a given generated timestamp.
  def canonicalize_time(scheduled_time)
    target_date = scheduled_time.in_time_zone(Time.zone).to_date
    wall_clock = schedule_wall_clock_time
    Time.zone.local(
      target_date.year,
      target_date.month,
      target_date.day,
      wall_clock.hour,
      wall_clock.min,
      wall_clock.sec
    )
  end

  def schedule_wall_clock_time
    event.start_time.in_time_zone(Time.zone)
  end

  def occurrence_for_local_date(local_date)
    local_day_start = Time.zone.local(local_date.year, local_date.month, local_date.day).beginning_of_day
    local_day_end = local_day_start.end_of_day

    candidates = event.occurrences.where(occurs_at: (local_day_start - 1.day)..(local_day_end + 1.day))
    candidates.select { |occ| occ.occurs_at.in_time_zone(Time.zone).to_date == local_date }
              .min_by(&:id)
  end

  def manually_rescheduled?(occurrence)
    postponed_replacement?(occurrence) || occurrence_moved_from_slug_date?(occurrence)
  end

  def postponed_replacement?(occurrence)
    target_date = occurrence.occurs_at.in_time_zone(Time.zone).to_date
    day_start = Time.zone.local(target_date.year, target_date.month, target_date.day).beginning_of_day
    day_end = day_start.end_of_day

    event.occurrences.postponed.where.not(id: occurrence.id)
         .exists?(postponed_until: day_start..day_end)
  end

  # Slugs are generated from occurs_at at creation and never updated when occurs_at changes.
  def occurrence_moved_from_slug_date?(occurrence)
    slug_date = occurrence.slug&.match(/(\d{4}-\d{2}-\d{2})/)&.[](1)
    return false if slug_date.blank?

    slug_date != occurrence.occurs_at.in_time_zone(Time.zone).strftime('%Y-%m-%d')
  end
end
