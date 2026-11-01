class EventOccurrencesController < ApplicationController # rubocop:disable Metrics/ClassLength
  include ReminderMessageBuilder
  include SchedulingFlashes

  before_action :set_occurrence, only: %i[show edit update destroy postpone cancel relocate reactivate
                                          post_slack_reminder post_social_reminder generate_ai_reminder
                                          send_host_reminder ical]
  before_action :authorize_occurrence, only: %i[edit update destroy postpone cancel relocate reactivate
                                                post_slack_reminder post_social_reminder generate_ai_reminder]
  before_action :authorize_admin, only: %i[send_host_reminder]

  def show
    @event = @occurrence.event
    @exclusive_conflicts = ScheduleConflictChecker.for_occurrence(@occurrence).blocks
    @current_rsvp = current_user && @occurrence.rsvps.active.find_by(user: current_user)
    store_location_for(:user, event_occurrence_path(@occurrence)) if !current_user && @occurrence.rsvp_open?
  end

  # Generate iCal file for a single occurrence (for Apple Calendar, etc.)
  def ical
    event = @occurrence.event
    builder = IcalBuilder.new(host: request.host,
                              organization_name: @site_config&.organization_name,
                              name: event.title)
    builder.add_occurrence(@occurrence, page_url: event_occurrence_url(@occurrence))

    send_data builder.to_ical,
              type: 'text/calendar',
              disposition: 'attachment',
              filename: "#{event.title.parameterize}-#{@occurrence.occurs_at.strftime('%Y-%m-%d')}.ics"
  end

  def edit
    @event = @occurrence.event
  end

  def update
    @event = @occurrence.event
    @occurrence.current_user_for_journal = current_user
    @occurrence.assign_attributes(occurrence_params)
    handle_image_selection

    blocks = exclusive_blocks_for(@occurrence)
    if blocks.any?
      @occurrence.errors.add(:base, SchedulingCopy.exclusive_block_text(blocks))
      render :edit, status: :unprocessable_content
      return
    end

    if @occurrence.save
      sync_rsvps_after_update
      result = ScheduleConflictChecker.for_occurrence(@occurrence)
      record_exclusive_override(@event, result.blocks)
      assign_scheduling_flashes(result)
      redirect_to @occurrence, notice: 'Occurrence was successfully updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @event = @occurrence.event
    @occurrence.destroy
    redirect_to @event, notice: 'Occurrence was successfully deleted.'
  end

  def postpone
    postponed_until = params[:postponed_until] ? Time.zone.parse(params[:postponed_until]) : 1.week.from_now
    preview = EventOccurrence.new(event: @occurrence.event, occurs_at: postponed_until, status: 'active')
    blocks = ScheduleConflictChecker.for_occurrence(preview).blocks
    if blocks.any? && !exclusive_override_requested?
      redirect_back_or_to @occurrence, alert: SchedulingCopy.exclusive_block_text(blocks)
      return
    end

    if @occurrence.postpone!(postponed_until, params[:reason], current_user)
      record_exclusive_override(@occurrence.event, blocks)
      assign_scheduling_flashes(ScheduleConflictChecker.for_occurrence(@occurrence.postponed_to)) if @occurrence.postponed_to
      redirect_back_or_to @occurrence.event, notice: 'Occurrence was postponed. A new occurrence has been created at the rescheduled date.'
    else
      redirect_back_or_to @occurrence, alert: 'Failed to postpone occurrence.'
    end
  end

  def cancel
    if @occurrence.cancel!(params[:reason], current_user)
      redirect_to @occurrence, notice: 'Occurrence was cancelled.'
    else
      redirect_to @occurrence, alert: 'Failed to cancel occurrence.'
    end
  end

  def relocate
    if params[:relocated_to].blank?
      redirect_to @occurrence, alert: 'New location is required.'
      return
    end

    if @occurrence.relocate!(params[:relocated_to], params[:reason], current_user)
      redirect_to @occurrence, notice: 'Occurrence was marked as relocated.'
    else
      redirect_to @occurrence, alert: 'Failed to mark occurrence as relocated.'
    end
  end

  def reactivate
    blocks = ScheduleConflictChecker.for_occurrence(@occurrence).blocks
    if blocks.any? && !exclusive_override_requested?
      redirect_to @occurrence, alert: SchedulingCopy.exclusive_block_text(blocks)
      return
    end

    if @occurrence.reactivate!(current_user)
      record_exclusive_override(@occurrence.event, blocks)
      assign_scheduling_flashes(ScheduleConflictChecker.for_occurrence(@occurrence))
      redirect_to @occurrence, notice: 'Occurrence was reactivated.'
    else
      redirect_to @occurrence, alert: 'Failed to reactivate occurrence.'
    end
  end

  def post_slack_reminder
    site_config = SiteConfig.current
    unless site_config.slack_enabled? && @occurrence.event.slack_announce?
      respond_to do |format|
        format.html { redirect_to @occurrence, alert: 'Slack reminders are disabled for this occurrence.' }
        format.json { render json: { success: false, message: 'Slack reminders are disabled for this occurrence.' } }
      end
      return
    end

    label = timing_label_for(@occurrence)
    message = long_reminder_message(@occurrence, label)
    if SlackService.post_occurrence_reminder(@occurrence, message)
      respond_to do |format|
        format.html { redirect_to @occurrence, notice: 'Posted reminder to Slack.' }
        format.json { render json: { success: true, message: 'Posted reminder to Slack.' } }
      end
    else
      respond_to do |format|
        format.html { redirect_to @occurrence, alert: 'Failed to post to Slack.' }
        format.json { render json: { success: false, message: 'Failed to post to Slack.' } }
      end
    end
  end

  def post_social_reminder
    site_config = SiteConfig.current
    unless site_config.social_reminders_enabled? && @occurrence.event.social_reminders?
      Rails.logger.info "post_social_reminder: Disabled - site=#{site_config.social_reminders_enabled?}, event=#{@occurrence.event.social_reminders?}"
      respond_to do |format|
        format.html { redirect_to @occurrence, alert: 'Social reminders are disabled for this occurrence.' }
        format.json { render json: { success: false, message: 'Social reminders are disabled for this occurrence.' } }
      end
      return
    end

    Rails.logger.info "post_social_reminder: Posting for occurrence #{@occurrence.id} (#{@occurrence.event.title})"
    label = timing_label_for(@occurrence)
    short_parts = reminder_message_with_link(@occurrence, label, message_type: :short)
    long_parts = reminder_message_with_link(@occurrence, label, message_type: :long)
    if SocialService.post_occurrence_reminder(@occurrence, short_parts: short_parts, long_parts: long_parts)
      respond_to do |format|
        format.html { redirect_to @occurrence, notice: 'Posted reminder to social media.' }
        format.json { render json: { success: true, message: 'Posted reminder to social media.' } }
      end
    else
      Rails.logger.warn "post_social_reminder: SocialService.post_occurrence_reminder returned false"
      error_msg = 'Failed to post to social media. Check that credentials are configured.'
      respond_to do |format|
        format.html { redirect_to @occurrence, alert: error_msg }
        format.json { render json: { success: false, message: error_msg } }
      end
    end
  end

  def generate_ai_reminder
    days_ahead = params[:days].to_i
    days_ahead = 6 unless [1, 6].include?(days_ahead)
    message_type = params[:type] == 'long' ? :long : :short

    unless OllamaService.configured?
      render json: { success: false, message: 'AI server not configured.' }
      return
    end

    generated_text = if message_type == :long
                       OllamaService.generate_long_reminder(@occurrence, days_ahead)
                     else
                       OllamaService.generate_short_reminder(@occurrence, days_ahead)
                     end

    if generated_text.present?
      render json: { success: true, message: generated_text }
    else
      render json: { success: false, message: 'Failed to generate AI reminder. Check server logs.' }
    end
  end

  def send_host_reminder
    site_config = SiteConfig.current
    @event = @occurrence.event

    return redirect_to @occurrence, alert: 'Host email reminders are disabled.' unless site_config.host_email_reminders_enabled?

    hosts = @event.hosts.where(email_reminders_enabled: true)
    return redirect_to @occurrence, alert: 'No hosts with email reminders enabled.' if hosts.empty?

    reminder_type = determine_reminder_type(@event, site_config)
    days_until = (@occurrence.occurs_at.to_date - Date.current).to_i
    test_email = site_config.email_test_mode_enabled? ? site_config.email_test_mode_address : nil

    hosts.each do |host|
      HostReminderMailer.upcoming_reminder_notification(
        user: host, occurrence: @occurrence, reminder_type: reminder_type,
        days_until_event: days_until, recipient_email: test_email || host.email
      ).deliver_now
    end

    notice = "Host reminder sent to #{hosts.count} #{'host'.pluralize(hosts.count)}"
    notice += " (test mode: #{test_email})" if test_email.present?
    redirect_to @occurrence, notice: notice
  end

  private

  def set_occurrence
    @occurrence = EventOccurrence.friendly_find(params[:id])
  end

  def authorize_occurrence
    @event = @occurrence.event
    return if current_user && (current_user.admin? || @event.hosted_by?(current_user))

    redirect_to @occurrence, alert: "You are not authorized to manage this occurrence."
  end

  def authorize_admin
    return if current_user&.admin?

    redirect_to @occurrence, alert: "You must be an admin to perform this action."
  end

  def occurrence_params
    attrs = params.expect(event_occurrence: %i[occurs_at custom_description custom_description_html duration_override status
                                               location_id capacity_override rsvp_disabled
                                               reminder_7d_short reminder_1d_short
                                               reminder_7d_long reminder_1d_long]).to_h.stringify_keys
    EventDescription.assign_pair(
      attrs,
      html_key: 'custom_description_html',
      text_key: 'custom_description',
      sync: params[:sync_custom_description].present?
    )
    return attrs if attrs['occurs_at'].blank?

    attrs.merge('occurs_at' => Time.zone.parse(attrs['occurs_at'].to_s))
  end

  def handle_image_selection
    source = effective_image_source
    return if source.blank?

    case source
    when 'inherit'
      return unless @occurrence.custom_event_image?

      selected = EventImageSelector.new(@occurrence.event).select(use_last_occurrence: false)
      @occurrence.assign_attributes(event_image: selected, custom_event_image: false)
    when 'pool'
      pool_image = @occurrence.event.event_images.find_by(id: params.dig(:event_occurrence, :event_image_id))
      @occurrence.assign_attributes(event_image: pool_image, custom_event_image: true) if pool_image
    when 'upload'
      custom_file = params.dig(:event_occurrence, :custom_image)
      return if custom_file.blank?

      in_pool = params.dig(:event_occurrence, :add_custom_image_to_pool) == '1'
      next_position = @occurrence.event.event_images.maximum(:position).to_i + 1
      event_image = @occurrence.event.event_images.create!(position: next_position, in_pool: in_pool)
      event_image.image.attach(custom_file)
      @occurrence.assign_attributes(event_image: event_image, custom_event_image: true)
    end
  end

  # Picking a pool image or a file without also switching the source radio
  # still means "use this image": the pool radios always submit the current
  # image, so a different id is a deliberate choice.
  def effective_image_source
    source = params.dig(:event_occurrence, :image_source)
    return 'upload' if params.dig(:event_occurrence, :custom_image).present? && source != 'pool'

    chosen_id = params.dig(:event_occurrence, :event_image_id)
    return 'pool' if chosen_id.present? && chosen_id.to_i != @occurrence.event_image_id

    source
  end

  def exclusive_blocks_for(occurrence)
    return [] unless occurrence.will_save_change_to_occurs_at? || occurrence.will_save_change_to_duration_override?

    blocks = ScheduleConflictChecker.for_occurrence(occurrence).blocks
    return [] if blocks.empty? || exclusive_override_requested?

    blocks
  end

  def sync_rsvps_after_update
    # Cancellation, relocation, postponement, and date or duration edits email
    # hosts and RSVPs from the occurrence callback. Capacity still has to be
    # applied after the save so a larger cap can offer open spots.
    RsvpLifecycle.occurrence_capacity_changed!(@occurrence)
  end

  def determine_reminder_type(event, site_config)
    return 'slack' if event.slack_announce? && site_config.slack_enabled?
    return 'social' if event.social_reminders? && site_config.social_reminders_enabled?

    'general'
  end

  def timing_label_for(occurrence)
    days_until = (occurrence.occurs_at.to_date - Date.current).to_i

    case days_until
    when ..(-1) then 'recently' # Past event
    when 0 then 'today'
    when 1 then 'tomorrow'
    when 2..6 then "#{days_until} days"
    when 7 then '1 week'
    else "#{days_until} days"
    end
  end
end
