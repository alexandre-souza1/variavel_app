require "test_helper"

class Prolog::TiresClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :parsed_response) do
    def success?
      code.to_i.between?(200, 299)
    end
  end

  test "returns the smallest installed tire depth by plate across pages" do
    responses = [
      Response.new(200, {
        "content" => [
          {
            "smallestTreadDepth" => 6.4,
            "installed" => { "licensePlate" => "FML6122" }
          }
        ],
        "lastPage" => false
      }),
      Response.new(200, {
        "content" => [
          {
            "smallestTreadDepth" => 4.54,
            "installed" => { "licensePlate" => "FML6122" }
          },
          {
            "smallestTreadDepth" => 1.2,
            "installed" => {
              "licensePlate" => "FML6122",
              "installedPositionName" => "ETP1",
              "installedAxle" => 9
            }
          }
        ],
        "lastPage" => true
      })
    ]

    http_client = Class.new do
      class << self
        attr_accessor :responses

        def get(*)
          responses.shift
        end
      end
    end
    http_client.responses = responses

    result = Prolog::TiresClient.new(token: "token", http_client: http_client)
      .tread_depth_by_plate

    assert_equal 4.54, result.fetch("FML6122")
    assert_equal 4.54, result.fetch("FML6B22")
  end

  test "does not call the API without a token" do
    http_client = Class.new do
      def self.get(*)
        raise "API não deveria ser chamada"
      end
    end

    assert_equal({}, Prolog::TiresClient.new(token: nil, http_client: http_client).tread_depth_by_plate)
  end
end
