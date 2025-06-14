class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :only_admin

  def index
    @users = User.all.order(:id)
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    if @user.update(user_params)
      redirect_to admin_users_path, notice: "Usuário atualizado com sucesso."
    else
      render :edit, alert: "Erro ao atualizar o usuário."
    end
  end

  def destroy
    @user = User.find(params[:id])
    if @user == current_user
      redirect_to admin_users_path, alert: "Você não pode deletar a si mesmo."
    else
      @user.destroy
      redirect_to admin_users_path, notice: "Usuário excluído com sucesso."
    end
  end

  private

  def only_admin
    redirect_to root_path, alert: "Acesso negado" unless current_user.admin?
  end

  def user_params
    permitted = [:email, :name, :role, :photo]
    permitted << :password if params[:user][:password].present?
    permitted << :password_confirmation if params[:user][:password_confirmation].present?
    params.require(:user).permit(permitted)
  end
end
