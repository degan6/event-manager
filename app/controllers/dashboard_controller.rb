class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @site_config = SiteConfig.current

    # Get events where the current user is a host (includes events they created)
    @hosted_events = Event.joins(:event_hosts)
                          .where(event_hosts: { user_id: current_user.id })
                          .includes(:location, :hosts, :event_occurrences)
                          .order(updated_at: :desc)

    # Get upcoming occurrences for hosted events
    @upcoming_occurrences = EventOccurrence
                            .joins(:event)
                            .joins("INNER JOIN event_hosts ON event_hosts.event_id = events.id")
                            .where(event_hosts: { user_id: current_user.id })
                            .where('event_occurrences.occurs_at >= ?', Time.current)
                            .includes(event: %i[hosts location])
                            .order(occurs_at: :asc)
                            .limit(20)

    @my_rsvps = Rsvp.active.where(user: current_user)
                    .joins(:event_occurrence)
                    .where(event_occurrences: { occurs_at: Time.current.. })
                    .includes(event_occurrence: :event)
                    .order('event_occurrences.occurs_at')
    @rsvp_counts = Rsvp.confirmed.where(event_occurrence_id: @upcoming_occurrences.map(&:id)).group(:event_occurrence_id).count

    @my_favorites = current_user.favorites.includes(:event, :event_occurrence).select do |favorite|
      favorite.event && policy(favorite.event).show?
    end
    @favorite_upcoming = Favorite.upcoming_for(current_user)
    @favorite_rsvp_ids = Rsvp.active.where(user: current_user, event_occurrence_id: @favorite_upcoming.map(&:first).map(&:id)).pluck(:event_occurrence_id)
  end
end
