class EmployeeCareerEvent < ApplicationRecord
  belongs_to :employee
  belongs_to :user
  def readonly? = persisted?
end
