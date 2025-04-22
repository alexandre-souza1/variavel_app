class AjudantesController < ApplicationController
  before_action :set_ajudante, only: %i[show edit update destroy]

  def index
    @ajudantes = Ajudante.all
  end

  def import
  end

  def import_csv
    file = params[:file]

    if file.nil?
      redirect_to import_ajudantes_path, alert: "Selecione um arquivo CSV para importar."
      return
    end

    require "csv"

    begin
      CSV.foreach(file.path, headers: true, col_sep: ";", encoding: "ISO-8859-1:utf-8") do |row|
        Ajudante.create!(
          matricula: row["matricula"],
          promax: row["promax"].to_s.strip.to_i.to_s,
          nome: row["nome"],
          cpf: row["cpf"],
          data_nascimento: row["data_nascimento"]
        )
      end

      redirect_to ajudantes_path, notice: "Ajudantes importados com sucesso!"
    rescue => e
      redirect_to import_ajudantes_path, alert: "Erro ao importar: #{e.message}"
    end
  end

  def show
  end

  def new
    @ajudante = Ajudante.new
  end

  def create
    @ajudante = Ajudante.new(ajudante_params)
    if @ajudante.save
      redirect_to @ajudante, notice: "Motorista criado com sucesso."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @ajudante.update(ajudante_params)
      redirect_to @ajudante, notice: "Motorista atualizado com sucesso."
    else
      render :edit
    end
  end

  def destroy
    @ajudante.destroy
    redirect_to ajudantes_path, notice: "Motorista apagado com sucesso."
  end

  def destroy_all
    @ajudante.delete_all
    redirect_to ajudantes_path, notice: "Todos os Ajudantes foram apagados com sucesso."
  end

  private

  def set_ajudante
    @ajudante = Ajudante.find(params[:id])
  end

  def ajudante_params
    params.require(:ajudante).permit(:nome, :matricula, :promax, :cpf, :data_nascimento)
  end
end
