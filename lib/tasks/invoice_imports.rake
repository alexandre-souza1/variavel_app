namespace :invoices do
  desc "Importa as notas de abastecimento de uma data (AAAA-MM-DD); padrão: ontem"
  task :import_abastecimento, [:date] => :environment do |_task, args|
    date = args[:date].present? ? Date.iso8601(args[:date]) : Time.zone.yesterday.to_date
    AbastecimentoEmailImportJob.perform_now(nil, date)
  end
end
