class ParametroCalculosController < ApplicationController
  before_action :set_parametro_calculo, only: %i[show edit update destroy]
  before_action :authenticate_user!
  before_action :check_permissions, only: %i[edit create update import destroy index show]

  def check_permissions
    case action_name
    when "destroy"
      redirect_back fallback_location: root_path, alert: "Acesso negado" unless current_user.admin?

    when "edit", "create", "update"
      unless current_user.admin? || current_user.supervisor?
        redirect_back fallback_location: root_path, alert: "Acesso negado"
      end

    when "import"
      unless current_user.admin? || current_user.supervisor? || current_user.user?
        redirect_back fallback_location: root_path, alert: "Acesso negado"
      end

    when "index", "show"
      unless current_user.admin? || current_user.supervisor? || current_user.user?
        redirect_back fallback_location: root_path, alert: "Acesso negado"
      end

    else
      # padrão: negar se não for admin
      redirect_back fallback_location: root_path, alert: "Acesso negado" unless current_user.admin?
    end
  end


  # GET /parametro_calculos
  def index
    @parametro_calculos_por_categoria = ParametroCalculo.all.group_by(&:categoria)
  end

  # GET /parametro_calculos/1
  def show
  end

  # GET /parametro_calculos/new
  def new
    @parametro_calculo = ParametroCalculo.new
  end

  # POST /parametro_calculos
  def create
    @parametro_calculo = ParametroCalculo.new(parametro_calculo_params)

    if @parametro_calculo.save
      redirect_to @parametro_calculo, notice: 'Parâmetro de cálculo criado com sucesso.'
    else
      render :new
    end
  end

  # GET /parametro_calculos/1/edit
  def edit
  end

  # PATCH/PUT /parametro_calculos/1
  def update
    if @parametro_calculo.update(parametro_calculo_params)
      redirect_to @parametro_calculo, notice: 'Parâmetro de cálculo atualizado com sucesso.'
    else
      render :edit
    end
  end

  def import
  end

  def import_csv

    require 'csv'

    if params[:file].present?
      CSV.foreach(params[:file].path, headers: true, col_sep: ";", encoding: "ISO-8859-1:utf-8") do |row|
        ParametroCalculo.create!(
          nome: row["nome"],
          categoria: row["categoria"],
          valor: row["valor"]
        )
      end
      redirect_to parametro_calculos_path, notice: "Parâmetros importados com sucesso!"
    else
      redirect_to import_csv_parametro_calculos_path, alert: "Por favor, selecione um arquivo CSV."
    end
  end

  # DELETE /parametro_calculos/1
  def destroy
    @parametro_calculo.destroy
    redirect_to parametro_calculos_url, notice: 'Parâmetro de cálculo excluído com sucesso.'
  end

  private

    def set_parametro_calculo
      @parametro_calculo = ParametroCalculo.find(params[:id])
    end

    def parametro_calculo_params
      params.require(:parametro_calculo).permit(:nome, :valor, :categoria)
    end
end
