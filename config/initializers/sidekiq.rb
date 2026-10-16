redis_url = ENV["REDIS_URL"].presence || ENV["REDISCLOUD_URL"].presence

if redis_url.present?
  Sidekiq.configure_server do |config|
    config.redis = { url: redis_url }
  end

  Sidekiq.configure_client do |config|
    config.redis = { url: redis_url }
  end
end

Sidekiq.configure_server do |config|
  scheduler = nil
  config.on(:startup) { scheduler = Automations::Scheduler.new; scheduler.start }
  config.on(:quiet) { scheduler&.stop }
  config.on(:shutdown) { scheduler&.stop }
end
