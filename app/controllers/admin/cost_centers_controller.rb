# app/controllers/admin/cost_centers_controller.rb
class Admin::CostCentersController < ApplicationController
  before_action :set_cost_center, only: [:edit, :update, :destroy]

  def index
    @cost_centers = CostCenter.all.order(:sector, :name)
  end

  def new
    @cost_center = CostCenter.new
  end

  def create
    @cost_center = CostCenter.new(cost_center_params)
    if @cost_center.save
      redirect_to admin_cost_centers_path, notice: 'Centro de custo criado com sucesso.'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @cost_center.update(cost_center_params)
      redirect_to admin_cost_centers_path, notice: 'Centro de custo atualizado com sucesso.'
    else
      render :edit
    end
  end

  def destroy
    @cost_center.destroy
    redirect_to admin_cost_centers_path, notice: 'Centro de custo excluído com sucesso.'
  end

  private

  def set_cost_center
    @cost_center = CostCenter.find(params[:id])
  end

  def cost_center_params
    params.require(:cost_center).permit(:name, :sector)
  end
end
