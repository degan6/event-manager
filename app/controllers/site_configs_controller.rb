class SiteConfigsController < ApplicationController
  AI_KEY_MASK = '*******'.freeze

  before_action :authenticate_user!, except: [:location]
  before_action :set_site_config
  before_action :authorize_site_config, except: [:location]

  def location
    # Public location page - no authentication required
  end

  def edit
    @ollama_models = OllamaService.available_models
  end

  def update
    # Handle favicon removal
    @site_config.favicon.purge if params[:site_config][:remove_favicon] == '1'

    # Handle banner removal
    @site_config.banner_image.purge if params[:site_config][:remove_banner_image] == '1'

    # Remove the removal flags from params before updating
    params[:site_config].delete(:remove_favicon)
    params[:site_config].delete(:remove_banner_image)
    params[:site_config].delete(:ai_key) if unchanged_ai_key_submitted?

    # Only update if there are params remaining after removing flags
    if params[:site_config].present? && @site_config.update(site_config_params)
      redirect_to edit_site_config_path, notice: 'Site configuration was successfully updated.'
    elsif params[:site_config].blank?
      # Just removed attachments, no other updates
      redirect_to edit_site_config_path, notice: 'Site configuration was successfully updated.'
    else
      @ollama_models = OllamaService.available_models
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_site_config
    @site_config = SiteConfig.current
  end

  def authorize_site_config
    authorize @site_config
  end

  def site_config_params
    params.expect(
      site_config: %i[organization_name
                      website_url
                      contact_email
                      contact_phone
                      footer_text
                      location_info
                      address
                      favicon
                      banner_image
                      slack_enabled
                      social_reminders_enabled
                      host_email_reminders_enabled
                      rsvps_enabled
                      rsvp_offer_hours
                      rsvp_last_call_hours
                      rsvp_guest_retention_days
                      email_test_mode_enabled
                      email_test_mode_address
                      ai_url
                      ai_key
                      ai_reminder_prompt
                      ai_model
                      short_reminder_max_length
                      long_reminder_max_length
                      matomo_enabled
                      matomo_url
                      matomo_site_id
                      disallow_robots
                      default_conflict_buffer_minutes
                      host_contact_response]
    )
  end

  def unchanged_ai_key_submitted?
    submitted_key = params[:site_config][:ai_key]

    submitted_key.blank? || submitted_key == AI_KEY_MASK
  end
end
