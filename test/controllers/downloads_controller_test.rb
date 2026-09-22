require "test_helper"

class DownloadsControllerTest < ActionDispatch::IntegrationTest
  test "redirects a valid Google Drive URL to the external host" do
    download = downloads(:google_drive)

    get open_download_path(download)

    assert_response :redirect
    assert_redirected_to download.url
  end

  test "does not redirect an invalid external URL" do
    download = downloads(:google_drive)
    download.update_column(:url, "https://example.com/file.pdf")

    get open_download_path(download)

    assert_redirected_to downloads_path
    assert_equal "URL inválida. Apenas links compartilhados do Google Drive ou Microsoft OneDrive são permitidos.", flash[:alert]
  end
end
