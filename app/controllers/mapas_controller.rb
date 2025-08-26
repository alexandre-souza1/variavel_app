class MapasController < ApplicationController
  before_action :authenticate_user!
  before_action :only_admin, only: [:destroy_all, :delete_by_month, :bulk_delete]
  before_action :admin_or_supervisor, only: [:destroy, :edit, :update]
  before_action :everyone_can_access, only: [:index, :import, :show_todos]

  def only_admin
    redirect_back fallback_location: root_path, alert: "Acesso negado" unless current_user.admin?
  end

  def admin_or_supervisor
    unless current_user.admin? || current_user.supervisor?
      redirect_back fallback_location: root_path, alert: "Acesso negado"
    end
  end

  def everyone_can_access
    unless current_user.admin? || current_user.supervisor? || current_user.user?
      redirect_back fallback_location: root_path, alert: "Acesso negado"
    end
  end
  def index
  end

  def edit
    @mapa = Mapa.find(params[:id])
  end

  def update
    @mapa = Mapa.find(params[:id])
    if @mapa.update(mapa_params)
      # Atualiza o fator baseado nos ajudantes
      ajudante1 = @mapa.matric_ajudante
      ajudante2 = @mapa.matric_ajudante_2

      count = [ajudante1, ajudante2].count { |a| a.present? && a != 0 && a != '0' }

      @mapa.update(fator: count.to_f) # 0.0, 1.0 ou 2.0

      redirect_to mapas_path, notice: "Ajudantes atualizados e fator ajustado para #{count.to_f}."
    else
      render :edit, alert: "Houve um erro ao atualizar."
    end
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

  def bulk_delete
    if params[:mapa_ids].present?
      Mapa.where(id: params[:mapa_ids]).destroy_all
      redirect_to mapas_todos_path, notice: 'Mapas selecionados foram apagados com sucesso.'
    else
      redirect_to mapas_todos_path, alert: 'Nenhum mapa foi selecionado.'
    end
  end

  def delete_by_month
    month = params[:month]
    if month.present?
      count = 0

      Mapa.find_each do |mapa|
        if mapa.data.present?
          # Remove caracteres não numéricos
          digits = mapa.data.gsub(/\D/, '')

          # Determina as posições do mês baseado no tamanho
          month_positions = case digits.length
                              when 8 then 2..3  # Formato ddMMyyyy
                              when 7 then 1..2  # Formato dMMyyyy
                              when 6 then 1..1  # Formato dMyyyy
                              else next
                            end

          # Extrai o mês e formata com 2 dígitos
          extracted_month = digits[month_positions].rjust(2, '0')

          if extracted_month == month
            mapa.destroy
            count += 1
          end
        end
      end

      redirect_to mapas_todos_path, notice: "#{count} mapas do mês #{month} foram apagados."
    else
      redirect_to mapas_todos_path, alert: 'Nenhum mês foi selecionado.'
    end
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
          pdv_total: row["QtEntregasCarreg(RV)"].to_s.gsub(",", ".").to_f,
          pdv_real: row["QtEntregasEntreg(RV)"].to_s.gsub(",", ".").to_f,
          recarga: row["Recarga"],
          matric_motorista: row["MatricMotorista"].to_s.strip.to_i.to_s,
          matric_ajudante: row["MatricAjud1"].to_s.strip.to_i.to_s,
          matric_ajudante_2: row["MatricAjud2"].to_s.strip.to_i.to_s
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

  private

  def mapa_params
    params.require(:mapa).permit(:matric_ajudante, :matric_ajudante_2)
  end
end
