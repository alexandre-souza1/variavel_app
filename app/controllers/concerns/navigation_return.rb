require "uri"

module NavigationReturn
  extend ActiveSupport::Concern

  private

  # Only accept an explicit return to one of the journey's GET entry points.
  # Keeping the query string preserves filters without relying on browser history.
  def safe_navigation_return_path(candidate, fallback:, allowed_paths:)
    return fallback unless candidate.is_a?(String)
    return fallback unless candidate.start_with?("/") && !candidate.start_with?("//")
    return fallback if candidate.match?(/[\\\x00-\x20\x7f]/)

    uri = URI.parse(candidate)
    return fallback if uri.scheme || uri.host || !allowed_paths.include?(uri.path)

    candidate
  rescue URI::InvalidURIError
    fallback
  end
end
