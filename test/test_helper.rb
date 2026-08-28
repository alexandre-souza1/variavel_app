ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "devise/test/integration_helpers"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  include Devise::Test::IntegrationHelpers

  setup do
    users(:one).update!(role: :admin)
    sign_in users(:one)
  end

    # Add more helper methods to be used by all tests here...
  end
end
