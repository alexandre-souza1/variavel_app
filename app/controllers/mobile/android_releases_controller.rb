module Mobile
  class AndroidReleasesController < ApplicationController
    before_action :authenticate_user!
    before_action { response.headers["Cache-Control"] = "no-store" }

    def latest
      return head :bad_request unless AndroidRelease::CHANNELS.include?(params[:channel])
      release = AndroidRelease.latest(params[:channel])
      return head :no_content unless release

      render json: {
        application_id: AndroidRelease::APPLICATION_ID, channel: release.channel,
        version_code: release.version_code, version_name: release.version_name,
        notes: release.notes.to_s, sha256: release.sha256, byte_size: release.byte_size,
        apk_path: apk_mobile_android_release_path(release)
      }
    end

    def show
      @android_release = AndroidRelease.latest("release")
    end

    def apk
      release = AndroidRelease.available.find(params[:id])
      # Use durable Active Storage delivery; the APK never goes onto Heroku's ephemeral disk.
      redirect_to rails_blob_path(release.apk, disposition: "attachment"), status: :see_other
    end
  end
end
