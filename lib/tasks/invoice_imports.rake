namespace :invoices do
  desc "Importa as notas de abastecimento recebidas no dia anterior"
  task import_abastecimento: :environment do
    AbastecimentoEmailImportJob.perform_now
  end
end
