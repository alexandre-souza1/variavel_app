Rails.application.routes.draw do
  resources :az_ajudantes
  get 'az_consultas/index'
  get 'az_consultas/new'
  get 'az_consultas/show'

  namespace :admin do
    get 'users/index'
    get 'users/edit'
    get 'users/update'
  end

  devise_for :users
  get 'drivers/index'
  get 'drivers/new'
  get 'drivers/edit'
  get 'drivers/show'
  get 'consultas/new'
  get 'consultas/show'
  get "mapas/show_todos", to: "mapas#show_todos", as: :mapas_todos
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  root "common#home"
  get "consulta", to: "consultas#show"
  get "az_consulta", to: "az_consultas#show"

  resources :downloads
  resources :autonomies, only: [:new, :create, :index]

  resources :common do
    collection do
      get :home
      get :padroes
    end
  end

  resources :plates do
    collection { post :import }
  end

  resources :mapas do
    collection do
      delete :bulk_delete
      delete :delete_by_month
      post :import
      delete :destroy_all
    end
  end

  resources :az_mapas do
    collection do
      post :import
      delete :destroy_all
    end
  end

  resources :wms_tasks do
    collection do
      get 'new_import'
      post 'import'
    end
  end

  namespace :admin do
    resources :users, only: [:index, :edit, :update, :destroy]
  end

   resources :operators do
    collection do
      get :import
      post :import_csv
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
