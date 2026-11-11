module Users
  class SessionsController < Devise::SessionsController
    def new
      RsvpLogin.remember(self)
      super
    end

    def after_sign_in_path_for(resource)
      FavoriteLogin.finish(self, resource)
      RsvpLogin.finish(self, resource) || super
    end
  end
end
