class FavoriteLogin
  def self.finish(controller, user)
    target = controller.session.delete(:pending_favorite)
    return if target.blank?

    unless SiteConfig.current&.favorites_enabled?
      controller.flash[:alert] = 'Following events is turned off.'
      return
    end

    event = Event.find_by(id: target['event_id'])
    occurrence = event&.occurrences&.find_by(id: target['occurrence_id']) if target['occurrence_id']
    if event.nil? || (target['occurrence_id'] && occurrence.nil?) || !EventPolicy.new(user, event).show?
      controller.flash[:alert] = 'That event or date is no longer available to follow.'
      return
    end

    FavoriteService.follow!(user, event: event, occurrence: occurrence) unless user.favorites.exists?(event: event, event_occurrence: occurrence)
    controller.flash[:notice] = occurrence ? 'Following this date.' : 'Following every date.'
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    controller.flash[:alert] = 'You are already following that.'
  end
end
