Rails.application.routes.draw do
  devise_for :users
  get 'drivers/index'
  get 'drivers/new'
  get 'drivers/edit'
  get 'drivers/show'
  get 'consultas/new'
  get 'consultas/show'
  get "mapas/show_todos", to: "mapas#show_todos", as: :mapas_todos
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  root "consultas#new"
  get "consulta", to: "consultas#show"

  resources :mapas do
    collection do
      post :import
      delete :destroy_all
    end
  end


  resources :drivers do
    collection do
      get :import
      post :import_csv
      delete :destroy_all
    end
  end

  resources :ajudantes do
    collection do
      get :import
      post :import_csv
      delete :destroy_all
    end
  end

  resources :parametro_calculos do
    collection do
      get :import
      post :import_csv
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
