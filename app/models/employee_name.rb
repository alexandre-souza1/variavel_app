class EmployeeName < ApplicationRecord
  belongs_to :employee
  validates :name, :normalized_name, presence: true
  validates :normalized_name, uniqueness: { scope: :employee_id }
  before_validation { self.normalized_name = self.class.normalize(name) }

  def self.normalize(value)
    value.to_s.unicode_normalize(:nfkd).encode('ASCII', invalid: :replace, undef: :replace, replace: '')
      .downcase.gsub(/[^a-z0-9]+/, ' ').strip
  end

  def self.resolve(value)
    ids = owners(value)
    Employee.find(ids.first) if ids.one?
  end

  def self.owners(value)
    key = normalize(value)
    return [] if key.blank?
    where(employee_id: Employee.with_career_history.select(:id))
      .where('normalized_name = :key OR normalized_name LIKE :prefix', key: key, prefix: "#{sanitize_sql_like(key)} %")
      .distinct.limit(2).pluck(:employee_id)
  end

  def self.resolutions(keys)
    names = where(employee_id: Employee.with_career_history.select(:id)).pluck(:normalized_name, :employee_id)
    keys.to_h do |key|
      owners = names.filter_map { |name, id| id if name == key || name.start_with?("#{key} ") }.uniq
      [key, owners.one? ? owners.first : nil]
    end
  end
end
