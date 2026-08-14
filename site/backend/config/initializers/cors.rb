# Be sure to restart your server when you modify this file.

# The Next.js frontend (site/frontend) lives on a different origin, and calls
# /api/me with credentials: "include" to read the session cookie set by the
# OmniAuth callback. `credentials: true` requires an explicit origin allowlist —
# it cannot be combined with a wildcard "*".
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3000")

    resource "*",
      headers: :any,
      methods: %i[get post delete options],
      credentials: true
  end
end
