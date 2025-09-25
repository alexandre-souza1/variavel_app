require 'httparty'

class SuppliersController < ApplicationController
  before_action :set_supplier, only: [:edit, :update, :destroy]

  def index
    @suppliers = Supplier.all.order(:name)
  end

  def new
    @supplier = Supplier.new
  end

  def create
    @supplier = Supplier.new(supplier_params)
    if @supplier.save
      redirect_to suppliers_path, notice: "Fornecedor cadastrado com sucesso!"
    else
      flash.now[:alert] = "Erro ao cadastrar fornecedor"
      render :new
    end
  end

  def show
    set_supplier
  end

  def edit
  end

  def update
    if @supplier.update(supplier_params)
      redirect_to suppliers_path, notice: "Fornecedor atualizado com sucesso!"
    else
      flash.now[:alert] = "Erro ao atualizar fornecedor"
      render :edit
    end
  end

  def destroy
    @supplier.destroy
    redirect_to suppliers_path, notice: "Fornecedor excluído com sucesso!"
  end

  def search_cnpj
    cnpj = params[:cnpj].to_s.gsub(/\D/, "") # remove pontos, traços e barras
    return render json: { error: "CNPJ inválido" }, status: :bad_request if cnpj.length != 14

    response = HTTParty.get("https://www.receitaws.com.br/v1/cnpj/#{cnpj}")

    if response.code == 200
      data = JSON.parse(response.body) rescue nil
      if data && data["nome"]
        render json: { name: data["nome"], cnpj: data["cnpj"] }
      else
        render json: { error: "CNPJ não encontrado" }, status: :not_found
      end
    else
      render json: { error: "Erro na API" }, status: :bad_gateway
    end
  rescue => e
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def supplier_params
    params.require(:supplier).permit(:name, :cnpj)
  end

  def set_supplier
    @supplier = Supplier.find(params[:id])
  end
end
