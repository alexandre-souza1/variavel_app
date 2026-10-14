require "test_helper"
require_relative "../../support/android_release_helpers"

class Mobile::AndroidReleasesControllerTest < ActionDispatch::IntegrationTest
  include AndroidReleaseHelpers
  teardown { cleanup_apk_files }

  test "manifest and APK download require a signed in user" do
    release = create_android_release
    sign_out users(:one)
    get mobile_latest_android_release_path(channel: "release"), as: :json
    assert_response :unauthorized
    get apk_mobile_android_release_path(release)
    assert_redirected_to new_user_session_path
  end

  test "no published release returns no content and invalid channels are rejected" do
    get mobile_latest_android_release_path(channel: "release"), as: :json
    assert_response :no_content
    get mobile_latest_android_release_path(channel: "other"), as: :json
    assert_response :bad_request
  end

  test "manifest selects the highest published version in the requested channel" do
    create_android_release(version_code: 8)
    release = create_android_release
    create_android_release(channel: "debug", version_code: 50)
    create_android_release(version_code: 51, published: false)
    users(:one).update!(role: :mechanical)
    get mobile_latest_android_release_path(channel: "release"), as: :json
    assert_response :success
    manifest = response.parsed_body
    assert_equal 9, manifest["version_code"]
    assert_equal "release", manifest["channel"]
    assert_equal AndroidRelease::APPLICATION_ID, manifest["application_id"]
    assert_equal release.sha256, manifest["sha256"]
    assert_equal release.byte_size, manifest["byte_size"]
    assert_equal apk_mobile_android_release_path(release), manifest["apk_path"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "published APK uses Active Storage and withdrawn APK cannot be downloaded" do
    release = create_android_release
    get apk_mobile_android_release_path(release)
    assert_response :see_other
    assert_includes response.location, "/rails/active_storage/blobs/redirect/"
    release.update!(published: false)
    get apk_mobile_android_release_path(release)
    assert_response :not_found
  end

  test "old Android apps have a download page and menu entry" do
    create_android_release
    get mobile_app_update_path, headers: { "User-Agent" => "Workstation Android;" }
    assert_response :success
    assert_select "a[href=?]", mobile_app_update_path, text: /Atualizar aplicativo/
    assert_select "a", text: "Baixar APK"
    assert_select "a[href=?]", admin_android_releases_path
  end
end
