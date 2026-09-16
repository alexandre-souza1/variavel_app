require "googleauth"
require "net/http"
require "stringio"

class FirebasePush
  class DeliveryError < StandardError; end
  class ConfigurationError < StandardError; end

  def self.enabled?
    ENV["FIREBASE_SERVICE_ACCOUNT_JSON"].present?
  end

  def initialize
    @json = ENV.fetch("FIREBASE_SERVICE_ACCOUNT_JSON")
    @project = JSON.parse(@json).fetch("project_id")
    raise ConfigurationError, "Invalid Firebase project" unless @project.match?(/\A[a-z0-9-]+\z/)
  rescue KeyError, JSON::ParserError
    raise ConfigurationError, "Firebase service account is not configured"
  end

  def deliver(notification:, device:)
    uri = URI("https://fcm.googleapis.com/v1/projects/#{@project}/messages:send")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{access_token}"
    request["Content-Type"] = "application/json"
    # Data messages let Android check the active account before displaying anything.
    request.body = {
      message: {
        token: device.token,
        data: { user_id: notification.user_id.to_s, notification_id: notification.id.to_s,
                title: "Workstation", body: "Você tem uma nova notificação no sistema." },
        android: { priority: "HIGH", ttl: "86400s" }
      }
    }.to_json
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
      http.request(request)
    end
    return true if response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body) rescue {}
    unregistered = Array(body.dig("error", "details")).any? { |detail| detail["errorCode"] == "UNREGISTERED" }
    if unregistered
      device.destroy!
      return false
    end
    Rails.cache.delete(cache_key) if response.code == "401"
    raise DeliveryError, "FCM HTTP #{response.code}" # Do not log the response, credentials or token.
  end

  private

  def cache_key
    "firebase/access-token/#{Digest::SHA256.hexdigest(@json)}"
  end

  def access_token
    Rails.cache.fetch(cache_key, expires_in: 45.minutes) do
      credentials = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(@json), scope: "https://www.googleapis.com/auth/firebase.messaging"
      )
      credentials.fetch_access_token!.fetch("access_token")
    end
  rescue StandardError
    raise ConfigurationError, "Could not authenticate with Firebase"
  end
end
