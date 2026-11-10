module FavoritesHelper
  def favorites_enabled?
    SiteConfig.current&.favorites_enabled?
  end

  def favorite_frame_id(event, occurrence = nil)
    occurrence ? dom_id(occurrence, :favorite) : dom_id(event, :favorite)
  end

  def current_favorite(event:, occurrence: nil)
    return unless user_signed_in?

    if occurrence
      loaded_favorites.find { |favorite| favorite.event_occurrence_id == occurrence.id }
    else
      loaded_favorites.find { |favorite| favorite.event_id == event.id && favorite.event_favorite? }
    end
  end

  def following_whole_event?(event)
    current_favorite(event: event).present?
  end

  private

  def loaded_favorites
    @loaded_favorites ||= current_user.favorites.to_a
  end
end
