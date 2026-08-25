Rails.application.routes.draw do
  get 'labels/create'
  get 'fuel_consumptions/index'
  get 'fuel_consumptions/new'
  get 'fuel_consumptions/create'
  get 'checklist_items/create'
  get 'checklist_items/destroy'
  get 'checklist_templates/index'
  get 'checklist_templates/new'
  get 'checklist_templates/create'
  get 'checklist_templates/show'
  get 'dashboard/placas_por_setor', to: 'dashboards#placas_por_setor', as: 'placas_por_setor'
  get 'dashboard/mapas', to: 'dashboards#mapas', as: 'dashboard_mapas'
  get 'dashboard', to: 'dashboards#index', as: 'dashboard'
  mount ActionCable.server => '/cable'

  resources :az_ajudantes do
    collection do
      get :import
      post :import_csv
      delete :destroy_all
    end
  end
  get 'az_consultas/index'
  get 'az_consultas/new'
  get 'az_consultas/show'
  get 'az_consultas/import', to: 'az_consultas#import_form', as: :az_consultas_import
  post 'az_consultas/import', to: 'az_consultas#import', as: :import_az_consultas
  delete 'az_consultas/import/:id', to: 'az_consultas#destroy_import', as: :destroy_az_consultas_import

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
  get 'variaveis', to: 'common#home', defaults: { force_home: 'true' }, as: :variaveis
  get "consulta", to: "consultas#show"
  get "az_consulta", to: "az_consultas#show"

  resources :downloads do
    member do
      get :open
      get :qr_code
    end
  end

  resources :notifications, only: :destroy do
    patch :read, on: :member
    delete :destroy_all, on: :collection
  end

  resources :checklists do
    patch :autosave, on: :collection

    collection do
      get :historic
    end

    member do
      get :download_photos
      get :export_excel
      post :restart
    end
  end
  resources :fuel_consumptions, only: [:index, :new, :create]

  resources :checklist_templates do
    resources :checklist_items, only: [:new, :create, :edit, :update, :destroy]
  end

  resources :stress_tests, only: [:index] do
    collection do
      get :import, action: :import_page
      post :import
      get :imports
    end

    member do
      get :import_details
    end
  end

  resources :routine_templates do
    resource :generator,
            only: %i[new create],
            controller: :routine_generators

    resources :routine_categories do
      resources :routine_indicators do
        resources :routine_indicator_targets,
                  except: :show
      end
    end
  end

  resources :routines, only: %i[index show destroy] do
    resources :activities,
              only: :index,
              controller: :routine_activities
  end
  resources :routine_values, only: :update do
    resources :routine_comments,
              only: %i[index create destroy]
  end

  resources :autonomies do
    collection do
      get :dashboard
      get :check_registration
      get :plates
      get :export_csv
    end
  end

  resources :task_imports, only: [:new, :create]

  resource :fleet_availability_email_setting,
           only: %i[edit update],
           path: "fleet_availabilities/email_setting"

  resources :fleet_availabilities do
    member do
      patch :restore_standard_layout
      patch :lock
      patch :unlock
    end

    resources :fleet_availability_items,
              only: [:update]
  end
  resources :fleet_dimensionings, except: :show

  resources :action_plans do
    patch :sort_buckets, on: :member

    resources :buckets do
      member do
        get :done_tasks
        get :open_tasks
      end

      resources :tasks do
        member do
          patch :toggle_complete
        end

        resources :comments, only: [:create]
        resource :tasklist, only: [:create, :destroy]

        # 👇 ADICIONE ESTA LINHA
        resources :tasklist_items, only: [:create]
      end
    end
  end

  resources :labels, only: [:create]

  patch "tasks/:id/move", to: "tasks#move"

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
      post :import
      get :import_progress
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
      delete :delete_all
      get 'new_import'
      post 'import'
    end
  end

  # Rota custom para API
  get 'suppliers/search_cnpj', to: 'suppliers#search_cnpj'

  # CRUD completo normal
  resources :suppliers

  resources :budget_categories

  resources :invoices do
    post :scan_upload, on: :collection
    collection do
      get :dashboard
    end

    member do
      get :download_document
    end
  end

  namespace :admin do
    resources :users, only: [:index, :edit, :update, :destroy, :new, :create]
    resources :cost_centers
    resources :budget_categories do
      get :expenses, on: :member
    end
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

  resources :remuneration_periods do
    member do
      get :compare
      get :export_csv
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
