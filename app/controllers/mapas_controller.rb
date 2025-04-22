class MapasController < ApplicationController
  def index
  end

  def show_todos
    @mapas = Mapa.order(data: :desc)

    datas_validas = @mapas.map do |mapa|
      if mapa.data.present? && mapa.data.match?(/^\d{8}$/)
        begin
          Date.strptime(mapa.data, "%d%m%Y")
        rescue
          nil
        end
      end
    end.compact

    @data_inicio = datas_validas.min
    @data_fim = datas_validas.max
    @dias_periodo = (@data_fim - @data_inicio).to_i if @data_inicio && @data_fim
  end

  def import
    file = params[:file]

    if file.present?
      CSV.foreach(file.path, headers: true, col_sep: ";", encoding: "ISO-8859-1:utf-8") do |row|
        Mapa.create!(
          mapa: row["Mapa"],
          data: row["Data"],
          fator: row["Fator"].to_i,
          cx_total: row["CxCarreg"],
          cx_real: row["CxEntreg"],
          pdv_total: row["Entregas"],
          pdv_real: row["EntregasCompletas"],
          recarga: row["Recarga"],
          matric_motorista: row["MatricMotorista"],
          matric_ajudante: row["MatricAjud1"]
        )
      end

      redirect_to root_path, notice: "Mapas importados com sucesso!"
    else
      redirect_to mapas_path, alert: "Selecione um arquivo CSV."
    end
  end
end
