raise 'Somente banco de testes' unless Rails.env.test?

member = TimeOffMembership.find_by!(ajudante: Ajudante.find_by!(promax: '182'))
raise 'Prepare os dados e execute time_off_test.cjs antes deste teste.' if member.time_off_overrides.exists?
member.update!(starts_on: '2026-10-08')
puts 'Vigência futura do ajudante preparada para correção no banco de testes.'
