Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    ENV.fetch("GOOGLE_CLIENT_ID", nil),
    ENV.fetch("GOOGLE_CLIENT_SECRET", nil)
end

# The frontend's "Entrar com Google" link is a plain GET navigation to
# /auth/google_oauth2 (see site/frontend), not a CSRF-protected POST form —
# OmniAuth 2.x otherwise defaults to requiring POST here. Accepted trade-off
# for this v1 skeleton (no billing/sensitive data on Customer yet); revisit
# with omniauth-rails_csrf_protection before this ships with real billing.
OmniAuth.config.allowed_request_methods = %i[get post]

# Surface OmniAuth::AuthenticityError etc as a normal redirect to
# SessionsController#failure instead of a raw 500.
OmniAuth.config.on_failure = proc do |env|
  SessionsController.action(:failure).call(env)
end
