class Mapa < ApplicationRecord
  belongs_to :driver, foreign_key: :matric_motorista, primary_key: :promax, optional: true
end
