class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:authentik]

  has_many :events, dependent: :destroy # Events created by this user
  has_many :event_hosts, dependent: :destroy
  has_many :hosted_events, through: :event_hosts, source: :event # Events this user co-hosts
  has_many :event_journals, dependent: :nullify # Audit logs persist after user deletion
  has_many :rsvps, dependent: :nullify
  has_many :favorites, dependent: :destroy

  validates :username, length: { maximum: 100 }, allow_blank: true

  validates :role, inclusion: { in: %w[user admin] }
  validates :email, presence: true, uniqueness: true

  def admin?
    role == 'admin'
  end

  def recent_no_show_count
    rsvps.where(attended: false)
         .joins(:event_occurrence)
         .where(event_occurrences: { occurs_at: 90.days.ago..Time.current })
         .count
  end

  def self.from_omniauth(auth)
    # Find or create user
    user = where(provider: auth.provider, uid: auth.uid).first_or_initialize

    # Update user info on each login
    user.email = auth.info.email
    user.name = auth.info.name
    user.username = auth.info.nickname if auth.info.nickname.present?

    # Set role and permissions based on Authentik claims
    user.role = determine_role_from_auth(auth)
    user.can_create_events = determine_can_create_events_from_auth(auth, user.role)

    # Set password for new users
    user.password = Devise.friendly_token[0, 20] if user.new_record?

    user.save!
    Rsvp.link_guest_rsvps!(user)

    Rails.logger.info "User #{user.email} logged in with role: #{user.role}, can_create_events: #{user.can_create_events}"

    user
  end

  def self.determine_role_from_auth(auth)
    # Check if Authentik sends the is_admin claim in raw_info
    is_admin_claim = auth.extra&.raw_info&.[]('is_admin')

    # Handle both boolean true and string "true" from Authentik
    # Only set admin if explicitly true (boolean) or "true" (string)
    is_admin = [true, 'true'].include?(is_admin_claim)

    # Log for debugging
    role = is_admin ? 'admin' : 'user'
    Rails.logger.info "Role check for #{auth.info.email}: is_admin claim = #{is_admin_claim.inspect} " \
                      "(type: #{is_admin_claim.class}), setting role to #{role}"

    # Return admin if claim is explicitly true, otherwise user (safe default)
    is_admin ? 'admin' : 'user'
  end

  def self.determine_can_create_events_from_auth(auth, role)
    # Admins can always create events
    return true if role == 'admin'

    # Check if Authentik sends the is_event_host claim in raw_info
    is_event_host_claim = auth.extra&.raw_info&.[]('is_event_host')

    # Handle both boolean true and string "true" from Authentik
    can_create = [true, 'true'].include?(is_event_host_claim)

    Rails.logger.info "Event host check for #{auth.info.email}: is_event_host claim = #{is_event_host_claim.inspect} " \
                      "(type: #{is_event_host_claim.class}), can_create_events: #{can_create}"

    can_create
  end
end
