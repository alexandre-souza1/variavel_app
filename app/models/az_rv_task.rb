class AzRvTask < ApplicationRecord
  belongs_to :az_rv_import

  # A planilha usa a Data Última Associação para fechar as tarefas/refugo.
  scope :between, ->(start_date, end_date) { where(associated_at: start_date.beginning_of_day..end_date.end_of_day) }
end
