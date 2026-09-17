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

  test "returns installed tires below the retread threshold with operational details" do
    response = Response.new(200, {
      "content" => [
        {
          "serialNumber" => "FOGO-123",
          "smallestTreadDepth" => 3.5,
          "createdAt" => "2026-09-17T12:49:32.159384Z",
          "installed" => {
            "licensePlate" => "FML6122",
            "vehicleTypeName" => "TOCO ELÉTRICO"
          }
        },
        {
          "serialNumber" => "FOGO-456",
          "smallestTreadDepth" => 3.7,
          "installed" => { "licensePlate" => "ABC1234" }
        },
        {
          "serialNumber" => "ESTEPE-1",
          "smallestTreadDepth" => 1.0,
          "installed" => {
            "licensePlate" => "FML6122",
            "installedPositionName" => "ETP1",
            "installedAxle" => 9
          }
        }
      ],
      "lastPage" => true
    })

    http_client = Class.new do
      class << self
        attr_accessor :response

        def get(*)
          response
        end
      end
    end
    http_client.response = response

    result = Prolog::TiresClient.new(token: "token", http_client: http_client)
      .tires_needing_retread

    assert_equal 1, result.size
    assert_equal({
      plate: "FML6122",
      vehicle_type: "TOCO ELÉTRICO",
      fire_number: "FOGO-123",
      position: nil,
      smallest_tread_depth: 3.5,
      created_at: "2026-09-17T12:49:32.159384Z"
    }, result.first)
  end

  test "filters a plate across pages and equivalents without mixing other vehicles or spares" do
    responses = [
      Response.new(200, { "content" => [
        { "serialNumber" => "001", "smallestTreadDepth" => 6, "installed" => { "licensePlate" => "FML6122", "installedPositionName" => "DE" } },
        { "serialNumber" => "002", "smallestTreadDepth" => 1, "installed" => { "licensePlate" => "ABC1234" } }
      ], "lastPage" => false }),
      Response.new(200, { "content" => [
        { "serialNumber" => "003", "smallestTreadDepth" => 3.5, "installed" => { "licensePlate" => "FML6B22", "installedPositionName" => "TEE" } },
        { "serialNumber" => "004", "smallestTreadDepth" => "", "installed" => { "licensePlate" => "FML6122" } },
        { "serialNumber" => "005", "smallestTreadDepth" => 1, "installed" => { "licensePlate" => "FML6122", "installedAxle" => 9 } }
      ], "lastPage" => true })
    ]
    http = Object.new
    http.define_singleton_method(:get) { |*args| responses.shift }
    client = Prolog::TiresClient.new(token: "token", http_client: http)
    tires = client.tires_for_plate("fml-6b22")
    assert_equal %w[003 001 004], tires.map { |tire| tire[:fire_number] }
    assert_equal "TEE", tires.first[:position]
    assert_nil tires.last[:smallest_tread_depth]
    assert_nil client.error
  end

  test "distinguishes missing configuration and API failures from an empty result" do
    client = Prolog::TiresClient.new(token: nil)
    assert_empty client.tires_for_plate("FML6122")
    assert_equal :not_configured, client.error

    http = Object.new
    http.define_singleton_method(:get) { |*args| Response.new(503, {}) }
    client = Prolog::TiresClient.new(token: "token", http_client: http)
    assert_empty client.tires_for_plate("FML6122")
    assert_equal :unavailable, client.error
  end
end
