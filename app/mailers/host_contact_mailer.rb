class HostContactMailer < ApplicationMailer
  def notify(host, event, message, sender:, occurrence: nil)
    sender = sender.stringify_keys
    @host = host
    @event = event
    @from_email = sender.fetch('email')
    @from_name = sender['name']
    @message = message
    @occurrence = occurrence
    @site_config = SiteConfig.current
    @test_mode = EmailTestMode.test_mode?
    @url = occurrence ? event_occurrence_url(occurrence) : event_url(event)
    @when_label = occurrence&.occurs_at&.strftime('%A, %B %d, %Y at %I:%M %p')
    @sender = @from_name.present? ? "#{@from_name} (#{@from_email})" : @from_email

    mail(
      to: EmailTestMode.recipient_for(host.email),
      reply_to: reply_address,
      subject: subject_line
    )
  end

  private

  def reply_address
    return @from_email if @from_name.blank?

    address = Mail::Address.new(@from_email)
    address.display_name = @from_name
    address.to_s
  end

  def subject_line
    text = if @when_label
             "Message about #{@event.title} on #{@occurrence.occurs_at.strftime('%b %-d')}"
           else
             "Message about #{@event.title}"
           end
    "[#{@site_config&.organization_name || 'EventManager'}] #{text}"
  end
end
