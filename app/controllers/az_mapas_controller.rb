class AzMapasController < ApplicationController
  before_action :set_az_mapa, only: %i[ show edit update destroy ]

  # GET /az_mapas or /az_mapas.json
  def index
    @az_mapas = AzMapa.all

    @data_inicio = AzMapa.minimum(:data)
    @data_fim = AzMapa.maximum(:data)
    @dias_periodo = (@data_fim - @data_inicio).to_i if @data_inicio && @data_fim
  end

  # GET /az_mapas/1 or /az_mapas/1.json
  def show
  end

  # GET /az_mapas/new
  def new
    @az_mapa = AzMapa.new
  end

  # GET /az_mapas/1/edit
  def edit
  end

  # POST /az_mapas or /az_mapas.json
  def create
    @az_mapa = AzMapa.new(az_mapa_params)

    turnos = turnos_para(params[:az_mapa][:tipo])
      @az_mapa = AzMapa.new(
        tipo: params[:az_mapa][:tipo],
        data: params[:az_mapa][:data],
        resultado: params[:az_mapa][:resultado],
        turno: turnos
      )

    if @az_mapa.save
      redirect_to az_mapas_path, notice: "Mapa criado com sucesso."
    else
      redirect_to new_az_mapa_path, alert: "Erro: #{@az_mapa.errors.full_messages.to_sentence}"
    end
  end

  # PATCH/PUT /az_mapas/1 or /az_mapas/1.json
  def update
    respond_to do |format|
      if @az_mapa.update(az_mapa_params)
        format.html { redirect_to @az_mapa, notice: "Az mapa was successfully updated." }
        format.json { render :show, status: :ok, location: @az_mapa }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @az_mapa.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /az_mapas/1 or /az_mapas/1.json
  def destroy
    @az_mapa.destroy!

    respond_to do |format|
      format.html { redirect_to az_mapas_path, status: :see_other, notice: "Az mapa was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def destroy_all
    AzMapa.delete_all
    redirect_to az_mapas_path, notice: "Todos os lançamentos foram apagados com sucesso."
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_az_mapa
      @az_mapa = AzMapa.find(params[:id])
    end

  def turnos_para(tipo)
    case tipo.to_sym
    when :tempo_atendimento
      [0, 1, 2]  # A, B, C
    when :eficiencia_carregamento
      [0, 2]     # A, C
    when :eficiencia_descarga
      [1]        # B
    else
      []
    end
  end

    # Only allow a list of trusted parameters through.
    def az_mapa_params
      params.require(:az_mapa).permit(:data, :turno, :tipo, :resultado, :atingiu_meta)
    end
end
