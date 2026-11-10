# Records description, banner, title, and link edits made by a person.
# Automated saves (banner rotation, the nightly job) leave current_user_for_journal
# blank, so they are ignored.
class FavoriteContent
  class << self
    def record_event(event)
      actor = event.current_user_for_journal
      return if actor.blank?

      record(event, nil, 'description', actor) if description_changed?(event)
      record(event, nil, 'title', actor) if event.saved_change_to_title?
      record(event, nil, 'details', actor) if event.saved_change_to_more_info_url?
      record(event, nil, 'banner', actor) if event_banner_changed?(event)
    end

    def record_occurrence(occurrence)
      actor = occurrence.current_user_for_journal
      return if actor.blank?

      record(occurrence.event, occurrence, 'description', actor) if description_changed?(occurrence, prefix: 'custom_')
      record(occurrence.event, occurrence, 'banner', actor) if occurrence_banner_changed?(occurrence)
    end

    private

    def description_changed?(record, prefix: '')
      record.public_send(:"saved_change_to_#{prefix}description?") ||
        record.public_send(:"saved_change_to_#{prefix}description_html?")
    end

    def event_banner_changed?(event)
      return true if event.saved_change_to_image_selection_mode?

      event.image_selection_mode == 'fixed' && event.saved_change_to_fixed_event_image_id?
    end

    def occurrence_banner_changed?(occurrence)
      occurrence.saved_change_to_event_image_id? || occurrence.saved_change_to_custom_event_image?
    end

    def record(event, occurrence, kind, actor)
      FavoriteChange.record!(event: event, occurrence: occurrence, kind: kind, actor: actor)
    end
  end
end
