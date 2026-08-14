module Api
  class MeController < ApplicationController
    # GET /api/me
    def show
      return head :unauthorized unless current_customer

      render json: current_customer.as_json(only: %i[id email name avatar_url])
    end
  end
end
