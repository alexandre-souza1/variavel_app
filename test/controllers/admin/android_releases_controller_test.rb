require "test_helper"
require_relative "../../support/android_release_helpers"

class Admin::AndroidReleasesControllerTest < ActionDispatch::IntegrationTest
  include AndroidReleaseHelpers
  teardown { cleanup_apk_files }

  test "only administrators can publish or change availability" do
    release = create_android_release
    users(:one).update!(role: :user)
    get admin_android_releases_path
    assert_redirected_to root_path
    assert_no_difference "AndroidRelease.count" do
      post admin_android_releases_path, params: { android_release: { version_code: 10 } }
    end
    assert_redirected_to root_path
    patch admin_android_release_path(release), params: { android_release: { published: false } }
    assert_redirected_to root_path
    assert release.reload.published?
  end

  test "administrator publishes a version with notes and an authenticated download" do
    get admin_android_releases_path
    assert_response :success
    assert_select "input[type=file][name=?]", "android_release[apk_upload]"
    assert_difference "AndroidRelease.count", 1 do
      post admin_android_releases_path, params: { android_release: {
        channel: "release", version_code: 9, version_name: "0.4.1", notes: "Novidades", apk_upload: apk_upload,
        sha256: "forged", byte_size: 1, published: false
      } }
    end
    assert_redirected_to admin_android_releases_path
    release = AndroidRelease.order(:id).last
    assert_equal "Novidades", release.notes
    assert release.published?
    assert_equal Digest::SHA256.hexdigest(release.apk.download), release.sha256
    follow_redirect!
    assert_select "a[href=?]", apk_mobile_android_release_path(release)
  end

  test "validation errors render the publication form without saving" do
    assert_no_difference "AndroidRelease.count" do
      post admin_android_releases_path, params: { android_release: { channel: "release", version_code: 9, version_name: "0.4.1" } }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]"
  end

  test "withdrawal does not modify the published binary or metadata" do
    release = create_android_release
    patch admin_android_release_path(release), params: { android_release: { published: false, version_code: 999, sha256: "forged" } }
    assert_redirected_to admin_android_releases_path
    assert_not release.reload.published?
    assert_equal 9, release.version_code
    assert_equal Digest::SHA256.hexdigest(release.apk.download), release.sha256
  end
end
