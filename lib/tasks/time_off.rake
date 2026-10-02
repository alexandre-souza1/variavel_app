namespace :time_off do
  desc 'Vincula a composição do piloto 5x2 aos cadastros ativos, sem criar pessoas ou sobrescrever grupos'
  task setup: :environment do
    schedule = TimeOff::PilotSetup.schedule
    result = TimeOff::PilotSetup.call(schedule: schedule)
    puts "#{result[:created]} participantes vinculados."
    result[:pending].each { |entry| puts "Pendente: #{entry['group']} · #{entry['name']} (#{entry['role']})" }
  end
end
