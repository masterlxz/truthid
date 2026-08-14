class Identity < ApplicationRecord
  belongs_to :customer

  validates :provider, presence: true
  validates :uid, presence: true, uniqueness: { scope: :provider }

  # Finds (or creates, alongside its Customer) the Identity for an
  # OmniAuth::AuthHash. Shared entry point for every provider — Google today,
  # GitHub/TruthID later — so SessionsController stays provider-agnostic.
  def self.find_or_create_from_omniauth(auth)
    identity = find_by(provider: auth.provider, uid: auth.uid)
    return identity if identity

    email = auth.info&.email
    customer = email.present? ? Customer.find_by(email: email) : nil
    customer ||= Customer.create!(
      email: email,
      name: auth.info&.name,
      avatar_url: auth.info&.image
    )

    customer.identities.create!(provider: auth.provider, uid: auth.uid)
  end
end
