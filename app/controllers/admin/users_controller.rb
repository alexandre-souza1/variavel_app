class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: [:edit, :update, :destroy]
  before_action :only_admin, except: [:edit, :update] # Aplica only_admin apenas para ações não relacionadas a edição
  before_action :authorize_user_edit, only: [:edit, :update] # Nova verificação para edit/update

  # ... (outras actions permanecem iguais)

  def update
    if params[:user][:remove_photo] == '1'
      @user.photo.purge
    end

    # Remove o role dos parâmetros se o usuário não for admin
    unless current_user.admin?
      params[:user].delete(:role)
    end

    if @user.update(user_params)
      if current_user.admin?
        redirect_to admin_users_path, notice: "Usuário atualizado com sucesso."
      else
        redirect_to edit_admin_user_path(@user), notice: "Perfil atualizado com sucesso."
      end
    else
      render :edit
    end
  end

  private

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
    permitted = [:email, :name, :photo, :remove_photo]
    permitted << :role if current_user.admin? # Só permite alterar role se for admin
    permitted << :password if password_params_present?
    permitted << :password_confirmation if password_params_present?
    params.require(:user).permit(permitted)
  end

  def password_params_present?
    params[:user][:password].present? || params[:user][:password_confirmation].present?
  end
end
