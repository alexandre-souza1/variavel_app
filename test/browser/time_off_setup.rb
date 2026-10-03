raise 'Somente banco de testes' unless Rails.env.test?
PcdChange.delete_all
PcdImport.delete_all
PcdPlan.delete_all
TimeOffVacation.delete_all
TimeOffChange.delete_all
TimeOffOverride.delete_all
TimeOffDailyPlan.delete_all
TimeOffMembership.delete_all
TimeOffSchedule.delete_all
schedule = TimeOff::PilotSetup.schedule
user = User.find_by!(email: 'user_one@example.com')
user.update!(role: :admin, password: 'password', password_confirmation: 'password')
Driver.order(:id).limit(2).each_with_index do |driver, index|
  driver.update_columns(nome: ['ADAIR DE ALMEIDA', 'CELIO MEDEIROS MOREIRA'][index], promax: ['2', '192'][index])
  schedule.time_off_memberships.create!(driver: driver, group_code: ['A', 'E'][index], starts_on: schedule.starts_on)
end
Ajudante.order(:id).limit(2).each_with_index do |helper, index|
  helper.update_columns(nome: ['PATRICK VIEIRA DA SILVA', 'ALBERTO RAMON FRUTOS'][index], promax: ['182', '170'][index])
  schedule.time_off_memberships.create!(ajudante: helper, group_code: ['A', 'FIXO'][index], fixed_weekday: index == 1 ? 6 : nil, standard_operation: index == 1 ? 'vespertina' : nil, starts_on: schedule.starts_on)
end
[['ADEMAR BERGMANN TELES', 'van', nil], ['ANDRE APARECIDO DA SILVA', 'motorista', 'vespertina'], ['KEBERSON PAULO TROIAN', 'motorista', 'as']].each_with_index do |(name, cargo, operation), index|
  employee = Employee.find_or_create_by!(matricula: "browser-coverage-#{index}") { |person| person.nome = name }
  employee.employee_roles.find_or_create_by!(cargo: cargo) { |role| role.assign_attributes(promax: "browser-coverage-#{index}", starts_on: schedule.starts_on, reason: 'Navegador: cadastro') }
  driver = Driver.find_or_create_by!(employee: employee) { |person| person.assign_attributes(nome: name, matricula: employee.matricula, promax: "browser-coverage-#{index}") }
  schedule.time_off_memberships.create!(driver: driver, group_code: 'FIXO', fixed_weekday: 6, standard_operation: operation, starts_on: schedule.starts_on)
end
FleetDimensioning.where(label: 'Navegador · Outubro 2026').destroy_all
FleetDimensioning.create!(label: 'Navegador · Outubro 2026', start_date: '2026-10-01', end_date: '2026-10-31', route_quantity: 18, vespertina_quantity: 1, as_quantity: 1, van_quantity: 1)
Plate.find_or_create_by!(placa: 'AAA1B23') { |plate| plate.assign_attributes(setor: 'ROTA', tipo: 'Caminhão') }
puts 'Dados do navegador preparados no banco de testes.'
