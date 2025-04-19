class Mapa < ApplicationRecord
  belongs_to :driver, foreign_key: :matric_motorista, primary_key: :promax, optional: true
  belongs_to :ajudante, foreign_key: :matric_ajudante, primary_key: :promax, optional: true
end
