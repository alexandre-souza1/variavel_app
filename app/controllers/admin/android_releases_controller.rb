class Admin::AndroidReleasesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  def index
    @android_release = AndroidRelease.new
    load_releases
  end

  def create
    @android_release = AndroidRelease.new(params.require(:android_release).permit(
      :channel, :version_code, :version_name, :notes, :apk_upload
    ))
    if @android_release.save
      redirect_to admin_android_releases_path, notice: "Versão disponibilizada para atualização no aplicativo.", status: :see_other
    else
      load_releases
      render :index, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @android_release.errors.add(:version_code, "já foi publicado neste canal")
    load_releases
    render :index, status: :unprocessable_entity
  end

  def update
    release = AndroidRelease.find(params[:id])
    release.update!(params.require(:android_release).permit(:published))
    redirect_to admin_android_releases_path, notice: "Disponibilidade da versão atualizada.", status: :see_other
  end

  private

  def load_releases
    @android_releases = AndroidRelease.with_attached_apk.order(created_at: :desc).limit(30)
  end
end
