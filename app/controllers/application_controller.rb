class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Method

  before_action :load_site_config
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_robots_header

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def pagy(type, collection, **)
    super
  rescue Pagy::RangeError => e
    super(type, collection, **, page: e.pagy.last)
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[name email_reminders_enabled favorite_emails_enabled])
  end

  private

  def load_site_config
    @site_config = SiteConfig.current
  end

  def set_robots_header
    return unless @site_config&.disallow_robots?

    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
  end

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_to(request.referer || root_path)
  end
end
