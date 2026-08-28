namespace :fleet_availabilities do
  desc "Fecha disponibilidades vencidas e abre a disponibilidade do próximo dia"
  task daily: :environment do
    result = FleetAvailabilities::DailyOpening.call
    puts "Disponibilidade: #{result.availability&.date || result.skipped_reason || 'já existente'}"
    puts "Fechadas: #{result.locked_count}"
  end
end
