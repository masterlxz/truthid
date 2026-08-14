class ApplicationController < ActionController::API
  private

  def current_customer
    @current_customer ||= Customer.find_by(id: session[:customer_id])
  end
end
