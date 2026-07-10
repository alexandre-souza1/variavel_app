class StressTestEvent < ApplicationRecord
  belongs_to :stress_test_import
  belongs_to :plate, optional: true
end
