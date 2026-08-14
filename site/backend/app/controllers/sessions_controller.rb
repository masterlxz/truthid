class SessionsController < ApplicationController
  # GET /auth/:provider/callback
  def create
    auth = request.env["omniauth.auth"]
    identity = Identity.find_or_create_from_omniauth(auth)
    session[:customer_id] = identity.customer_id

    redirect_to "#{frontend_url}/dashboard", allow_other_host: true
  end

  # GET /auth/failure
  def failure
    reason = params[:message].presence || "oauth_failed"
    redirect_to "#{frontend_url}/?error=#{ERB::Util.url_encode(reason)}", allow_other_host: true
  end

  # DELETE /logout
  def destroy
    session[:customer_id] = nil
    head :no_content
  end

  private

  def frontend_url
    ENV.fetch("FRONTEND_URL", "http://localhost:3000")
  end
end
