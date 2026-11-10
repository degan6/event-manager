module FavoritesHelper
  def favorites_enabled?
    SiteConfig.current&.favorites_enabled?
  end

  def favorite_frame_id(event, occurrence = nil)
    occurrence ? dom_id(occurrence, :favorite) : dom_id(event, :favorite)
  end

  def favorite_variant(occurrence, variant: nil, compact: false)
    return variant if %w[plain date series compact].include?(variant)
    return 'compact' if compact

    occurrence ? 'date' : 'plain'
  end

  def favorite_labels(variant)
    {
      'date' => ['Follow this date', 'Following this date'],
      'series' => ['Follow every date', 'Following every date']
    }.fetch(variant, %w[Follow Following])
  end

  def favorite_form_params(event:, occurrence: nil, variant: 'plain', context_occurrence: nil)
    {
      event_id: event.id,
      event_occurrence_id: occurrence&.id,
      variant: variant,
      context_occurrence_id: context_occurrence&.id
    }.compact
  end

  def favorite_display_params(variant:, context_occurrence: nil)
    { variant: variant, context_occurrence_id: context_occurrence&.id }.compact
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
