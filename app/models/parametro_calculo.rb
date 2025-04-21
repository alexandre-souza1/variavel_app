class ParametroCalculo < ApplicationRecord
  validates :categoria, presence: true

  NOME_VALOR_CAIXA   = "valor_caixa"
  NOME_VALOR_ENTREGA = "valor_entrega"
  NOME_VALOR_RECARGA = "valor_recarga"

  NOME_VALOR_CAIXA_AJUDANTE   = "valor_caixa_ajudante"
  NOME_VALOR_ENTREGA_AJUDANTE = "valor_entrega_ajudante"
  NOME_VALOR_RECARGA_AJUDANTE = "valor_recarga_ajudante"

  NOME_VALOR_BONUS_DEVOLUCAO = "valor_bonus_devolucao"
end
