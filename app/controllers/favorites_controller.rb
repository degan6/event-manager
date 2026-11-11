class FavoritesController < ApplicationController
  skip_forgery_protection only: :unsubscribe
  before_action :authenticate_user!, except: %i[unsubscribe login]
  before_action :ensure_enabled, except: %i[unsubscribe login]

  def create
    load_target
    load_presentation
    authorize @event, :show?
    FavoriteService.follow!(current_user, event: @event, occurrence: @occurrence)
    respond_with_toggle
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_back_or_to fallback_path, alert: 'You are already following that.'
  end

  def destroy
    favorite = current_user.favorites.find(params.expect(:id))
    @event = favorite.event
    @occurrence = favorite.event_occurrence
    load_presentation
    favorite.destroy!
    respond_with_toggle
  end

  def reminders
    favorite = current_user.favorites.find(params.expect(:id))
    favorite.update!(reminders_enabled: !favorite.reminders_enabled)
    notice = favorite.reminders_enabled? ? 'Reminders are on.' : 'Reminders are off. You will still hear about changes.'
    redirect_back_or_to dashboard_path, notice: notice
  end

  def unsubscribe
    favorite = Favorite.find_by_token_for(:unsubscribe, params[:token])
    if favorite&.destroy
      redirect_to root_path, notice: 'You will no longer get emails about that.'
    else
      redirect_to root_path, alert: 'That link has expired.'
    end
  end

  def login
    load_target
    session[:pending_favorite] = { "event_id" => @event.id, "occurrence_id" => @occurrence&.id }
    store_location_for(:user, safe_return_path)
    redirect_to new_user_session_path
  end

  private

  def ensure_enabled
    return if SiteConfig.current&.favorites_enabled?

    redirect_back_or_to root_path, alert: 'Following events is turned off.'
  end

  def load_target
    if params[:event_occurrence_id].present?
      @occurrence = EventOccurrence.friendly_find(params[:event_occurrence_id])
      @event = @occurrence.event
    else
      @event = Event.friendly_find(params[:event_id])
    end
  end

  def load_presentation
    @variant = params[:variant].to_s
    @variant = 'plain' unless %w[plain date series compact].include?(@variant)
    return if params[:context_occurrence_id].blank?

    @context_occurrence = @event.occurrences.find_by(id: params[:context_occurrence_id])
  end

  def respond_with_toggle
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back_or_to fallback_path }
    end
  end

  def fallback_path
    @occurrence ? event_occurrence_path(@occurrence) : event_path(@event)
  end

  def safe_return_path
    target = params[:return_to].to_s
    return target if target.start_with?('/') && !target.start_with?('//')

    root_path
  end
end
