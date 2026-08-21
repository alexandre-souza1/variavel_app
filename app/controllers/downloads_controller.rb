class DownloadsController < ApplicationController

  before_action :set_download, only: [:edit, :update, :destroy]
  before_action :authenticate_user!, only: [:new, :create, :edit, :update, :destroy]

  def index
    @downloads = Download
      .with_attached_file
      .order(:category, :title)
  end

  def new
    @download = Download.new
  end

  def create
    @download = Download.new(download_params)

    if @download.save
      redirect_to downloads_path,
                  notice: "Download adicionado com sucesso!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @download.update(download_params)
      redirect_to downloads_path,
                  notice: "Download atualizado com sucesso!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @download.destroy

    redirect_to downloads_path,
                notice: "Download removido com sucesso!"
  end

  private

  def set_download
    @download = Download.find(params[:id])
  end

  def download_params
    params.require(:download).permit(
      :title,
      :description,
      :category,
      :file_type,
      :sector,
      :url,
      :file
    )
  end

end
