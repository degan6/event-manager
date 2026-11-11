class OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # OAuth callbacks come from external providers and cannot include CSRF tokens.
  # Protection is provided by:
  # 1. OmniAuth's state parameter (validated automatically)
  # 2. The omniauth-rails_csrf_protection gem (requires POST for OAuth initiation)
  # 3. Verification that the OAuth response matches the initiated request
  protect_from_forgery with: :null_session, only: :authentik

  def authentik
    # Verify the OmniAuth response is present and valid
    auth = request.env['omniauth.auth']
    unless auth&.provider == 'authentik' && auth&.uid.present?
      Rails.logger.warn "Invalid OAuth callback: missing or invalid auth data"
      return redirect_to root_path, alert: 'Authentication failed. Invalid response from provider.'
    end

    @user = User.from_omniauth(auth)

    if @user.persisted?
      sign_in(@user, event: :authentication)
      path = after_sign_in_path_for(@user)
      set_flash_message(:notice, :success, kind: 'Authentik') if is_navigational_format? && flash[:notice].blank?
      redirect_to path
    else
      session['devise.authentik_data'] = request.env['omniauth.auth'].except('extra')
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
    end
  end

  def failure
    redirect_to root_path, alert: 'Authentication failed. Please try again.'
  end

  def after_sign_in_path_for(resource)
    FavoriteLogin.finish(self, resource)
    RsvpLogin.finish(self, resource) || super
  end
end
