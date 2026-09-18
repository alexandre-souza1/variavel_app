module Prolog
  class TireMap
    # With the cab pointing left, the vehicle's right side is above the chassis.
    POSITIONS = {
      "DD" => ["front", 0], "DE" => ["front", 1],
      "D1D" => ["front", 0], "D1E" => ["front", 1],
      "D2D" => ["front_second", 0], "D2E" => ["front_second", 1],
      "TDE" => ["traction", 0], "TDI" => ["traction", 1],
      "TEI" => ["traction", 2], "TEE" => ["traction", 3],
      "TKDE" => ["truck", 0], "TKDI" => ["truck", 1],
      "TKEI" => ["truck", 2], "TKEE" => ["truck", 3],
      "TD" => ["truck", 0], "TE" => ["truck", 1]
    }.freeze

    attr_reader :axles, :unmapped_tires

    def initialize(layout, tires)
      @axles = Array(layout).map { |axle| { axle: axle, tires: Array.new(axle[:tires]) } }
      @unmapped_tires = []
      tires.reject { |tire| tire[:spare] }.each do |tire|
        key, slot = POSITIONS[tire[:position].to_s.strip.upcase]
        target = @axles.find { |entry| entry[:axle][:key] == key }
        # TD/TE describe a single rear wheel on each side, not a dual assembly.
        compatible = !%w[TD TE].include?(tire[:position].to_s.strip.upcase) || target&.dig(:axle, :tires) == 2
        if target && slot && slot < target[:tires].size && target[:tires][slot].nil? && compatible
          target[:tires][slot] = tire
        else
          @unmapped_tires << tire
        end
      end
    end
  end
end
