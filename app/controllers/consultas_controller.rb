class ConsultasController < ApplicationController
  def new
  end

  def show
    @matricula = params[:matricula]
    @driver = Driver.find_by(matricula: @matricula)

    if @driver
      @mapas = Mapa.where(matric_motorista: @driver.promax)

          # Extrair datas válidas e converter
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
    else
      flash.now[:alert] = "Matrícula não encontrada"
      render :new
    end
  end
end
