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

  def destroy
    @mapa = Mapa.find(params[:id])
    @mapa.destroy  # Destrói a instância específica
    redirect_to mapas_todos_path, notice: "Mapa apagado com sucesso."
  end

  def destroy_all
    Mapa.delete_all
    redirect_to mapas_todos_path, notice: "Todos os mapas foram apagados com sucesso."
  end

  def import
    file = params[:file]

    if file.present?
      mapas_no_arquivo = Set.new
      mapas_ignorados = []

      CSV.foreach(file.path, headers: true, col_sep: ";", encoding: "ISO-8859-1:utf-8") do |row|
        next unless row["Entrega"]&.strip == "Rota"

        numero_mapa = row["Mapa"].to_s.strip

        # Verifica duplicidade
        if Mapa.exists?(mapa: numero_mapa) || mapas_no_arquivo.include?(numero_mapa)
          mapas_ignorados << numero_mapa
          next
        end

        mapas_no_arquivo.add(numero_mapa)

        Mapa.create!(
          mapa: numero_mapa,
          data: row["Data"],
          fator: row["Fator"].to_i,
          cx_total: row["CxCarreg"].to_s.gsub(",", ".").to_f,
          cx_real: row["CxEntreg"].to_s.gsub(",", ".").to_f,
          pdv_total: row["Entregas"].to_s.gsub(",", ".").to_f,
          pdv_real: row["EntregasCompletas"].to_s.gsub(",", ".").to_f,
          recarga: row["Recarga"],
          matric_motorista: row["MatricMotorista"].to_s.strip.to_i.to_s,
          matric_ajudante: row["MatricAjud1"].to_s.strip.to_i.to_s
        )
      end

      notice_msg = "Mapas importados com sucesso!"
      if mapas_ignorados.any?
        notice_msg += " Os seguintes mapas foram ignorados por duplicidade: #{mapas_ignorados.uniq.sort.join(', ')}."
      end

      redirect_to mapas_todos_path, notice: notice_msg
    else
      redirect_to mapas_path, alert: "Selecione um arquivo CSV."
    end
  end

end
