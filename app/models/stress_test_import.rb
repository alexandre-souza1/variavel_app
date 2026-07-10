class StressTestImport < ApplicationRecord
  belongs_to :user

  has_many :stress_test_events, dependent: :destroy
end
