module AzRvEmployeeMatching
  extend ActiveSupport::Concern

  included do
    scope :for_employee, ->(name) do
      key = AzRvEmployeeMatching.normalize(name)
      where("employee_key = :key OR :key LIKE employee_key || ' %'", key: key)
    end
  end

  def self.normalize(name)
    name.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
        .downcase.gsub(/[^a-z0-9]+/, " ").strip
  end
end
