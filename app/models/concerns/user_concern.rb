module UserConcern

  extend ActiveSupport::Concern

  include ::GravatarImageTag


  included do
    has_secure_password

    has_many :conversations_users
    has_and_belongs_to_many :conversations, foreign_key: :user_id, join_table: :conversations_users

    has_many :followers, class_name: 'Following', foreign_key: :following_id
    has_many :follows, class_name: 'Following', foreign_key: :user_id

    validates :email, presence: true, uniqueness: true, format: { with: /\A[^@]+@[^@]+\.[a-zа-я]{2,6}\z/ }
    validates :password, length: { minimum: 6, if: :validate_password?, too_short: "не менее 6 символов" }
    # validates :phone, format: { with: /\A[+\-\(\)\d]+\z/ }, length: { in: 5..20 }, if: ->{ phone.present? }
    # validates_presence_of :firstname, :lastname, :phone, on: :update, if: ->{ role.present? }

    after_update :send_update_confirmation, :notify
  end


  %w(auth forgot).each do |name|
    define_method("generate_#{name}_token".to_sym) do
      public_send("#{name}_token=", Digest::MD5.hexdigest(Time.now.to_s + email)) if email.present?
    end

    define_method("generate_#{name}_token!".to_sym) do
      public_send("generate_#{name}_token")
      save validate: false
    end
  end


  def generate_cookie &block
    instance_exec { block.call({ value: "#{id}|#{auth_token}", expires: 1.month.from_now }) }
  end


  ROLES = %w[owner employee moderator admin]
  ROLES.each do |r|
    define_method("#{r}?") { r == role }
  end


  def name
    firstname && lastname ? "#{ firstname } #{ lastname }" : email
  end

  def update_password! values
    self.password = values['password']
    self.password_confirmation = values['password_confirmation']
    self.forgot_token = nil
    valid?
    save validate: false if errors[:password].empty? && errors[:password_confirmation].empty?
  end

  def update_personal_data! data
    self.firstname  = data[:firstname]
    self.lastname   = data[:lastname]
    profile_will_change!
    profile.reverse_merge! data[:profile]
    save
  end

  def avatar
    case profile['image_source']
    when 'custom' then profile['image']
    when 'gravatar' then gravatar_image_url(email)
    else '/no_avatar.jpg'
    end
  end

  def avatar_type
    profile['image_source'] || 'none'
  end


  def follows? user
    id = user.kind_of?(User) ? user.id : user
    !!follows.exists?(following_id: id)
  end

  def follow! user
    id = user.kind_of?(User) ? user.id : user
    follows.create following_id: id
  end

  def unfollow! user
    id = user.kind_of?(User) ? user.id : user
    follows.where(following_id: id).first.try :destroy
  end


  def unread_messages
    []
    # conversations.flat_map { |c| c.unread_messages self }.sort_by { |m| m.created_at }.reverse
  end

  def unread_messages_count
    conversations.map { |c| c.unread_messages_count self }.sum
  end


  protected

  def validate_password?
    password.present? || password_confirmation.present?
  end

  def send_update_confirmation
    AuthMailer.forgot(self).deliver if forgot_token_changed? && forgot_token
    AuthMailer.credentials(self).deliver if email_changed? || password_digest_changed?
  end

end