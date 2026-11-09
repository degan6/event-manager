class HostContactsController < ApplicationController
  rate_limit to: 5, within: 1.minute, only: :create, by: -> { request.remote_ip }

  def create
    load_target
    authorize @event, :show?
    return redirect_to(return_path, alert: 'This event is not accepting messages.') unless @event.allow_host_contact?
    return redirect_to(return_path, notice: visitor_response) if params[:company_website].present?
    return redirect_to(return_path, alert: 'This event has no hosts to contact.') if @event.hosts.none?

    contact = HostContact.new(email: params[:email], name: params[:name], message: params[:message])
    return redirect_to(return_path, alert: contact.errors.full_messages.to_sentence) unless contact.valid?

    contact.deliver_to(@event, occurrence: @occurrence)
    Rails.logger.info("Host contact sent for event #{@event.id} to #{@event.hosts.size} hosts")
    redirect_to return_path, notice: visitor_response
  end

  private

  def load_target
    if params[:event_occurrence_id].present?
      @occurrence = EventOccurrence.friendly_find(params[:event_occurrence_id])
      @event = @occurrence.event
    else
      @event = Event.friendly_find(params[:event_id])
    end
  end

  def return_path
    @occurrence ? event_occurrence_path(@occurrence) : event_path(@event)
  end

  def visitor_response
    SiteConfig.current.host_contact_response_text
  end
end
