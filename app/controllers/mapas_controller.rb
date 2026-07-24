class MapasController < ApplicationController
  before_action :authenticate_user!
  before_action :only_admin, only: [:destroy_all, :bulk_delete]
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
    @per_page = [[params.fetch(:per_page, 100).to_i, 25].max, 500].min
    @page = [params.fetch(:page, 1).to_i, 1].max

    @mapas_scope = aplicar_filtros_mapa(Mapa.all)
    @total_mapas = @mapas_scope.count
    @total_pages = (@total_mapas.to_f / @per_page).ceil
    @page = @total_pages if @total_pages.positive? && @page > @total_pages

    @mapas = @mapas_scope
              .order(created_at: :desc, id: :desc)
              .offset((@page - 1) * @per_page)
              .limit(@per_page)
              .to_a

    datas_validas = @mapas.filter_map(&:data_formatada)

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

  def import
    file = params[:file]

    if file.blank?
      redirect_to mapas_path, alert: "Selecione um arquivo CSV."
      return
    end

    mapas_no_arquivo = Set.new
    mapas_ignorados = []
    erros_importacao = []

    CSV.foreach(file.path, headers: true, col_sep: ";", encoding: "ISO-8859-1:utf-8").with_index(2) do |row, line|

      begin
        next unless row["Entrega"]&.strip == "Rota"

        numero_mapa = row["Mapa"].to_s.strip

        if numero_mapa.blank?
          erros_importacao << "Linha #{line}: mapa vazio"
          next
        end

        if Mapa.exists?(mapa: numero_mapa) || mapas_no_arquivo.include?(numero_mapa)
          mapas_ignorados << numero_mapa
          next
        end

        mapas_no_arquivo.add(numero_mapa)

        mapa = Mapa.new(
          mapa: numero_mapa,
          data: row["Data"],

          fator: begin
            m  = row["MatricMotorista"].to_s.strip
            a1 = row["MatricAjud1"].to_s.strip
            a2 = row["MatricAjud2"].to_s.strip

            if m.present? && m != "0" && a1.present? && a1 != "0" && a2.present? && a2 != "0"
              2
            elsif m.present? && m != "0" && a1.present? && a1 != "0"
              1
            else
              0
            end
          end,

          cx_total: row["CxCarreg"].to_s.gsub(",", ".").to_f,
          cx_real: row["CxEntreg"].to_s.gsub(",", ".").to_f,
          pdv_total: row["QtEntregasCarreg(RV)"].to_s.gsub(",", ".").to_f,
          pdv_real: row["QtEntregasEntreg(RV)"].to_s.gsub(",", ".").to_f,
          recarga: row["Recarga"],
          plate: row["Placa"].strip.presence,
          matric_motorista: row["MatricMotorista"].to_s.strip.presence,
          matric_ajudante: row["MatricAjud1"].to_s.strip.presence,
          matric_ajudante_2: row["MatricAjud2"].to_s.strip.presence
        )

        unless mapa.save
          erros_importacao << "Linha #{line} (Mapa #{numero_mapa}): #{mapa.errors.full_messages.join(', ')}"
        end

      rescue => e
        erros_importacao << "Linha #{line} (Mapa #{row['Mapa']}): erro inesperado - #{e.message}"
      end
    end

    notice_msg = "Importação finalizada!"

    if mapas_ignorados.any?
      notice_msg += " Ignorados (duplicados): #{mapas_ignorados.uniq.join(', ')}."
    end

    if erros_importacao.any?
      notice_msg += " Erros: #{erros_importacao.first(10).join(' | ')}"
    end

    redirect_to mapas_todos_path, notice: notice_msg
  end

  private

  def mapa_params
    params.require(:mapa).permit(:matric_ajudante, :matric_ajudante_2)
  end

  def aplicar_filtros_mapa(scope)
    if params[:mapa].present?
      scope = scope.where("mapa ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:mapa].strip)}%")
    end

    if params[:motorista].present?
      scope = scope.where("matric_motorista ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:motorista].strip)}%")
    end

    if params[:data].present?
      scope = scope.where("data ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:data].strip)}%")
    end

    if params[:ajudante].present?
      ajudante = "%#{ActiveRecord::Base.sanitize_sql_like(params[:ajudante].strip)}%"
      scope = scope.where("matric_ajudante ILIKE :ajudante OR matric_ajudante_2 ILIKE :ajudante", ajudante: ajudante)
    end

    if params[:mes].present?
      mes = params[:mes].to_s.rjust(2, "0")
      mes_sem_zero = mes.to_i.to_s
      scope = scope.where(
        "data LIKE :mes_com_barras OR data LIKE :mes_digitos OR data LIKE :mes_sem_zero",
        mes_com_barras: "%/#{mes}/%",
        mes_digitos: "__#{mes}____",
        mes_sem_zero: "_#{mes_sem_zero}____"
      )
    end

    if params[:ano].present?
      scope = scope.where("data LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:ano].strip)}")
    end

    scope
  end
end
