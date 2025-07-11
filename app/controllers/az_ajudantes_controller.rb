class AzAjudantesController < ApplicationController
  before_action :set_az_ajudante, only: %i[ show edit update destroy ]

  # GET /az_ajudantes or /az_ajudantes.json
  def index
    @az_ajudantes = AzAjudante.all
  end

  # GET /az_ajudantes/1 or /az_ajudantes/1.json
  def show
  end

  # GET /az_ajudantes/new
  def new
    @az_ajudante = AzAjudante.new
  end

  # GET /az_ajudantes/1/edit
  def edit
  end

  # POST /az_ajudantes or /az_ajudantes.json
  def create
    @az_ajudante = AzAjudante.new(az_ajudante_params)

    respond_to do |format|
      if @az_ajudante.save
        format.html { redirect_to @az_ajudante, notice: "Az ajudante was successfully created." }
        format.json { render :show, status: :created, location: @az_ajudante }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @az_ajudante.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /az_ajudantes/1 or /az_ajudantes/1.json
  def update
    respond_to do |format|
      if @az_ajudante.update(az_ajudante_params)
        format.html { redirect_to @az_ajudante, notice: "Az ajudante was successfully updated." }
        format.json { render :show, status: :ok, location: @az_ajudante }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @az_ajudante.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /az_ajudantes/1 or /az_ajudantes/1.json
  def destroy
    @az_ajudante.destroy!

    respond_to do |format|
      format.html { redirect_to az_ajudantes_path, status: :see_other, notice: "Az ajudante was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_az_ajudante
      @az_ajudante = AzAjudante.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def az_ajudante_params
      params.require(:az_ajudante).permit(:matricula, :nome, :cpf, :data_nascimento, :turno)
    end
end
