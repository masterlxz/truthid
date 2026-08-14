Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # OmniAuth's middleware owns GET/POST /auth/:provider (initiates the OAuth
  # dance) — only the callback and failure landing pages are real routes here.
  get "auth/:provider/callback", to: "sessions#create"
  get "auth/failure", to: "sessions#failure"
  delete "logout", to: "sessions#destroy"

  namespace :api do
    resource :me, only: :show, controller: "me"
  end
end
