require "test_helper"

class OauthLoginFlowTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "111122223333",
      info: {
        email: "ana@example.com",
        name: "Ana Souza",
        image: "https://example.com/avatar.png"
      }
    )
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test "google callback creates a Customer + Identity and starts a session api/me can read" do
    assert_difference [ "Customer.count", "Identity.count" ], 1 do
      get "/auth/google_oauth2/callback"
    end

    assert_redirected_to %r{\A#{Regexp.escape(ENV.fetch('FRONTEND_URL', 'http://localhost:3000'))}/dashboard\z}

    customer = Customer.find_by!(email: "ana@example.com")
    identity = customer.identities.sole
    assert_equal "google_oauth2", identity.provider
    assert_equal "111122223333", identity.uid

    get "/api/me"
    assert_response :success
    body = response.parsed_body
    assert_equal customer.id, body["id"]
    assert_equal "ana@example.com", body["email"]
    assert_equal "Ana Souza", body["name"]
  end

  test "logging in twice with the same google account reuses the same Customer" do
    get "/auth/google_oauth2/callback"
    first_customer_id = Customer.find_by!(email: "ana@example.com").id
    delete "/logout"

    assert_no_difference "Customer.count" do
      assert_no_difference "Identity.count" do
        get "/auth/google_oauth2/callback"
      end
    end

    get "/api/me"
    assert_equal first_customer_id, response.parsed_body["id"]
  end

  test "api/me returns 401 when there is no session" do
    get "/api/me"
    assert_response :unauthorized
  end

  test "omniauth failure redirects to the frontend with an error, without touching the db" do
    assert_no_difference [ "Customer.count", "Identity.count" ] do
      get "/auth/failure", params: { message: "access_denied" }
    end

    assert_redirected_to %r{\A#{Regexp.escape(ENV.fetch('FRONTEND_URL', 'http://localhost:3000'))}/\?error=access_denied\z}
  end
end
