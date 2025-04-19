class Ajudante < ApplicationRecord
  has_many :mapas, foreign_key: :matric_ajudante, primary_key: :promax
end
