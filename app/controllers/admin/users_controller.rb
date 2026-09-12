class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: [:edit, :update, :destroy]
  before_action :only_admin, except: [:index, :edit, :update]
  before_action :authorize_user_edit, only: [:edit, :update] # Nova verificação para edit/update

  def index
    load_user_index
    @selected_user = @users.find_by(id: params[:edit_user_id])
    @selected_user ||= @users.first unless current_user.admin?
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to admin_users_path, notice: "Usuário criado com sucesso."
    else
      Rails.logger.debug @user.errors.full_messages
      Rails.logger.debug @user.errors.to_hash

      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_user_index
    @selected_user = @user
    render :index
  end

  def update
    if params[:user][:remove_photo] == '1'
      @user.photo.purge
    end

    # Remove o role dos parâmetros se o usuário não for admin
    unless current_user.admin?
      params[:user].delete(:role)
    end

    if @user.update(user_params)
      load_user_index
      @selected_user = @user
      flash.now[:notice] = current_user.admin? ? "Usuário atualizado com sucesso." : "Perfil atualizado com sucesso."
      render :index
    else
      load_user_index
      @selected_user = @user
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to admin_users_path, alert: "Você não pode deletar a si mesmo."
    else
      @user.retire!
      redirect_to admin_users_path, notice: "Usuário inativado com sucesso. O histórico foi preservado."
    end
  end

  private

  def load_user_index
    scope = params[:status] == "inactive" ? User.inactive : User.active
    scope = scope.where(id: current_user.id) unless current_user.admin?
    @users = scope.order(:id)
  end

  def set_user
    @user = User.find(params[:id])
  end

  def authorize_user_edit
    unless current_user.admin? || @user == current_user
      redirect_to root_path, alert: "Acesso negado"
    end
  end

  def only_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Acesso restrito a administradores"
    end
  end

  def user_params
    permitted = [:email, :name, :photo, :remove_photo, :color_theme]

    if current_user.admin?
      permitted << :role
      permitted << :sector
    end

    permitted << :password if password_params_present?
    permitted << :password_confirmation if password_params_present?

    params.require(:user).permit(permitted)
  end

  def password_params_present?
    params[:user][:password].present? || params[:user][:password_confirmation].present?
  end
end
