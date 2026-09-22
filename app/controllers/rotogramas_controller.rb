class RotogramasController < ApplicationController
  def index
    @rotogramas = JSON.parse(Rails.root.join("config/rotogramas.json").read)
    @return_path = params[:origem] == "az" ? az_consultas_new_path : consultas_new_path
  end
end
