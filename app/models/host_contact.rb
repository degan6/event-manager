class HostContact
  include ActiveModel::Model

  attr_reader :email, :name, :message

  validates :email, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: 'must be a valid email' }, allow_blank: true
  validates :name, length: { maximum: 120 }, allow_blank: true
  validates :message, presence: true, length: { maximum: 4000 }

  def email=(value)
    @email = value.to_s.strip
  end

  def name=(value)
    @name = value.to_s.gsub(/[\r\n\u0000]/, ' ').squish.presence
  end

  def message=(value)
    @message = value.to_s.strip
  end

  def deliver_to(event, occurrence: nil)
    event.hosts.each do |host|
      HostContactMailer.notify(
        host, event, message, sender: { email: email, name: name }, occurrence: occurrence
      ).deliver_later
    end
  end
end
