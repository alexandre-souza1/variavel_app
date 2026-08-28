class Operator < ApplicationRecord
  has_many :wms_tasks
  has_many :autonomies, as: :user
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  def retire!
    update!(active: false, retired_at: Date.current)
  end
  def self.normalize_name(name)
    name.to_s.mb_chars.upcase.to_s.strip.gsub(/\s+/, ' ') # Remove espaços extras e normaliza
  end
end
