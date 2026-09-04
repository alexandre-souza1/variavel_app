namespace :fleet_availabilities do
  desc "Cria a disponibilidade do próximo dia"
  task daily_opening: :environment do
    FleetAvailabilitiesDailyJob.perform_now
  end
end
