class FavoriteService
  class << self
    def follow!(user, event:, occurrence: nil)
      raise Pundit::NotAuthorizedError unless EventPolicy.new(user, event).show?

      if occurrence
        user.favorites.create!(event: event, event_occurrence: occurrence)
      else
        user.favorites.create!(event: event)
      end
    end

    # A postponed date keeps its followers on the new date. Someone who already
    # follows the event, or the new date, does not get a second favorite.
    def transfer!(from_occurrence, to_occurrence)
      from_occurrence.favorites.find_each do |favorite|
        if covered?(favorite.user_id, to_occurrence)
          favorite.destroy!
        else
          favorite.update!(event: to_occurrence.event, event_occurrence: to_occurrence)
        end
      end
    end

    private

    def covered?(user_id, occurrence)
      Favorite.exists?(user_id: user_id, event_id: occurrence.event_id, event_occurrence_id: nil) ||
        Favorite.exists?(user_id: user_id, event_occurrence_id: occurrence.id)
    end
  end
end
