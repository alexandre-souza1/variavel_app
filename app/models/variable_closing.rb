class VariableClosing < ApplicationRecord
  require 'bigdecimal'

  belongs_to :employee
  belongs_to :user, optional: true
  validates :user, presence: true, unless: :legacy_baseline?
  validates :reason, :result, presence: true
  validates :month, inclusion: { in: 1..12 }
  validates :year, numericality: { only_integer: true, greater_than: 1900, less_than: 10000 }
  def readonly? = persisted?

  def self.capture!(employee:, user:, year:, month:, reason:)
    employee.with_lock do
      finish = Date.new(year, month, 20)
      start = finish.prev_month.change(day: 21)
      report = EmployeeVariableReport.new(employee, from: start, to: finish)
      report.validate!
      create!(employee: employee, user: user, year: year, month: month, reason: reason,
        revision: where(employee: employee, year: year, month: month).maximum(:revision).to_i + 1,
        result: report.snapshot)
    end
  end

  def self.merge_results(*results, employee:)
    maps = {}
    groups = {}
    roles = {}
    issues = []

    results.compact.each do |snapshot|
      snapshot.fetch('maps', []).each do |entry|
        source = entry.fetch('source')
        key = source['id'] || source[:id] || "#{source['mapa']}-#{maps.size}"
        maps[key] ||= entry
      end
      snapshot.fetch('groups', {}).each do |cargo, values|
        groups[cargo] ||= {}
        values.each do |key, value|
          next if key.to_s == 'percentual_devolucao'
          groups[cargo][key] = add_numeric(groups[cargo][key], value, integer: %w[quantidade_mapas total_mapas recargas].include?(key.to_s))
        end
      end
      snapshot.fetch('roles', []).each do |role|
        roles[role['id'] || role[:id]] ||= role
      end
      issues.concat(snapshot.fetch('issues', []))
    end

    totals = groups.empty? ? {} : MapaRemuneracaoService.new('motorista').totals([])
    groups.each_value do |group|
      group.each do |key, value|
        symbol_key = key.to_sym
        totals[symbol_key] = add_numeric(totals[symbol_key], value, integer: %i[quantidade_mapas total_mapas recargas].include?(symbol_key)) unless symbol_key == :percentual_devolucao
      end
    end
    unless totals.empty?
      totals[:percentual_devolucao] = totals[:pdv_real] + totals[:devolucoes] == 0 ? 0 : totals[:devolucoes] / (totals[:pdv_real] + totals[:devolucoes])
    end

    {
      'employee' => employee.attributes.slice('id', 'nome', 'matricula', 'cpf'),
      'totals' => totals,
      'groups' => groups,
      'roles' => roles.values,
      'maps' => maps.values,
      'issues' => issues.uniq,
      'rule' => 'Fechamento consolidado por período; cargos diferentes permanecem em grupos separados.'
    }
  end

  def self.add_numeric(current, value, integer: false)
    return value.to_i if current.nil? && integer
    return BigDecimal(value.to_s) if current.nil?
    integer ? current.to_i + value.to_i : BigDecimal(current.to_s) + BigDecimal(value.to_s)
  end

  def revise_cargo!(from_cargo:, to_cargo:, user:, reason:)
    from_cargo = from_cargo.to_s
    to_cargo = to_cargo.to_s
    valid_cargos = EmployeeRole::CARGOS.values
    unless valid_cargos.include?(from_cargo) && valid_cargos.include?(to_cargo) && from_cargo != to_cargo
      raise EmployeeRole::HistoryError, 'Selecione cargos válidos e diferentes para a revisão.'
    end
    raise EmployeeRole::HistoryError, 'Informe o motivo da revisão.' if reason.to_s.strip.blank?

    source_maps = result.fetch('maps', []).select { |entry| entry.dig('calculation', 'categoria') == from_cargo }
    raise EmployeeRole::HistoryError, "Não há mapas com o cargo #{EmployeeRole::CARGOS.key(from_cargo)} neste fechamento." if source_maps.empty?

    revised_maps = result.fetch('maps', []).map do |entry|
      source = entry.fetch('source')
      calculation = entry.fetch('calculation')
      cargo = calculation['categoria'] == from_cargo ? to_cargo : calculation['categoria']
      mapa = Mapa.new(source)
      values = MapaRemuneracaoService.new(cargo).values(mapa)
      updated = values.merge(role_id: calculation['role_id'], cargo_historico: calculation['cargo_historico'], cargo_override: cargo == calculation['categoria'] ? calculation['cargo_override'] : cargo)
      { source: source, calculation: updated }
    end

    groups = revised_maps.group_by { |entry| entry.dig(:calculation, :categoria) }.transform_values do |entries|
      cargo = entries.first.dig(:calculation, :categoria)
      MapaRemuneracaoService.new(cargo).totals(entries.map { |entry| Mapa.new(entry[:source]) })
    end
    totals = groups.empty? ? {} : MapaRemuneracaoService.new('motorista').totals([])
    groups.each_value do |group|
      group.each { |key, value| totals[key] += value unless key == :percentual_devolucao }
    end
    unless totals.empty?
      totals[:percentual_devolucao] = totals[:pdv_real] + totals[:devolucoes] == 0 ? 0 : totals[:devolucoes] / (totals[:pdv_real] + totals[:devolucoes])
    end

    self.class.create!(employee: employee, user: user, year: year, month: month,
      revision: self.class.where(employee: employee, year: year, month: month).maximum(:revision).to_i + 1,
      reason: reason.to_s.strip,
      result: result.merge(
        'totals' => totals,
        'groups' => groups,
        'maps' => revised_maps,
        'revision_of' => id,
        'revision_reason' => reason.to_s.strip,
        'rule' => "Revisão #{id}: cargo #{EmployeeRole::CARGOS.key(from_cargo)} alterado para #{EmployeeRole::CARGOS.key(to_cargo)} nos mapas selecionados."
      ))
  end
end
