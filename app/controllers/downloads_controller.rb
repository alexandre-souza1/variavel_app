class DownloadsController < ApplicationController
  before_action :set_download, only: [
    :edit,
    :update,
    :destroy,
    :open,
    :qr_code
  ]

  before_action :authenticate_user!, only: [
    :new,
    :create,
    :edit,
    :update,
    :destroy
  ]

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

  # ==========================================================
  # ABRIR DOCUMENTO
  # ==========================================================

  def open
    if @download.file.attached?
      redirect_to rails_blob_path(
        @download.file,
        disposition: "inline"
      )
    else
      redirect_to @download.url,
                  allow_other_host: true
    end
  end

  # ==========================================================
  # QR CODE
  # ==========================================================

  def qr_code
    qr = RQRCode::QRCode.new(
      open_download_url(@download)
    )

    svg = qr.as_svg(
      module_size: 8,
      standalone: true,
      use_path: true
    )

    if params[:download].present?
      send_data(
        svg,
        filename: "qr-code-#{@download.id}.svg",
        type: "image/svg+xml",
        disposition: "attachment"
      )
    else
      render body: svg,
             content_type: "image/svg+xml",
             layout: false
    end
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
