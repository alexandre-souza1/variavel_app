require "test_helper"
require_relative "../support/android_release_helpers"

class AndroidReleaseTest < ActiveSupport::TestCase
  include AndroidReleaseHelpers
  teardown { cleanup_apk_files }

  test "stores an immutable checksum and byte size for the uploaded APK" do
    upload = apk_upload
    expected = Digest::SHA256.file(upload.tempfile.path).hexdigest
    release = create_android_release(apk_upload: upload)
    assert_equal expected, release.sha256
    assert_equal upload.size, release.byte_size
    assert_equal expected, Digest::SHA256.hexdigest(release.apk.download)
    assert_equal "application/vnd.android.package-archive", release.apk.content_type
  end

  test "requires a valid APK and bounded version fields" do
    release = AndroidRelease.new(channel: "other", version_code: 0, version_name: "")
    assert_not release.valid?
    assert release.errors[:apk].any?
    assert release.errors[:channel].any?
    assert release.errors[:version_code].any?
    assert release.errors[:version_name].any?
  end

  test "rejects renamed text and a zip with no Android manifest" do
    file = Tempfile.new(["bad", ".apk"])
    begin
      file.write("not an APK"); file.flush
      release = AndroidRelease.new(channel: "release", version_code: 9, version_name: "0.4.1",
        apk_upload: Rack::Test::UploadedFile.new(file.path, "application/octet-stream"))
      assert_not release.valid?
      assert release.errors[:apk].any?
      Zip::OutputStream.open(file.path) { |zip| zip.put_next_entry("report.txt"); zip.write("report") }
      release.apk_upload = Rack::Test::UploadedFile.new(file.path, "application/octet-stream")
      assert_not release.valid?
      assert release.errors[:apk].any?
    ensure
      file.close!
    end
  end

  test "version codes are unique per channel and latest ignores withdrawn releases" do
    original = create_android_release
    debug = create_android_release(channel: "debug")
    duplicate = AndroidRelease.new(channel: "release", version_code: 9, version_name: "different", apk_upload: apk_upload)
    assert_not duplicate.valid?
    assert duplicate.errors[:version_code].any?
    create_android_release(version_code: 10, published: false)
    assert_equal original, AndroidRelease.latest("release")
    assert_equal debug, AndroidRelease.latest("debug")
    latest = create_android_release(version_code: 11)
    assert_equal latest, AndroidRelease.latest("release")
  end
end
