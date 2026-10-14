require "zip"
require "tempfile"

module AndroidReleaseHelpers
  def apk_upload
    file = Tempfile.new(["log-ia-test", ".apk"])
    (@apk_test_files ||= []) << file
    Zip::OutputStream.open(file.path) do |zip|
      zip.put_next_entry("AndroidManifest.xml")
      zip.write("test manifest")
    end
    Rack::Test::UploadedFile.new(file.path, "application/vnd.android.package-archive")
  end

  def create_android_release(**attributes)
    AndroidRelease.create!({ channel: "release", version_code: 9, version_name: "0.4.1",
                             notes: "Melhorias no aplicativo", apk_upload: apk_upload }.merge(attributes))
  end

  def cleanup_apk_files
    @apk_test_files&.each(&:close!)
  end
end
