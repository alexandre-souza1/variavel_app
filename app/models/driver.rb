class Driver < ApplicationRecord
  has_many :mapas, foreign_key: :matric_motorista, primary_key: :promax
end
