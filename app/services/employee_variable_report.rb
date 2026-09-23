class EmployeeVariableReport
  attr_reader :employee, :maps, :issues

  def initialize(employee, from: nil, to: nil, maps: nil)
    @employee = employee
    candidates = (maps || employee.maps).to_a
    @issues = []
    @roles = {}
    @services = {}
    @values = {}
    codes = employee.employee_roles.map(&:promax)
    other_roles = EmployeeRole.where(promax: codes).where.not(employee_id: employee.id).to_a
    @maps = candidates.select do |mapa|
      date = mapa.data_formatada
      unless date
        @issues << "Mapa #{mapa.mapa}: data inválida; não foi calculado."
        next false
      end
      next false if (from && date < from) || (to && date > to)
      role = employee.role_for(mapa)
      other_owners = other_roles.select { |item| item.covers?(date) && item.matches_map?(mapa) }
      if role && other_owners.any?
        @issues << "Mapa #{mapa.mapa}: Promax atribuído a mais de um colaborador nessa data. Revise os vínculos no RH."
        next false
      end
      next false if role.nil? && other_owners.any?
      unless role
        @issues << "Mapa #{mapa.mapa}: cargo ou Promax sem vigência correspondente em #{date.strftime('%d/%m/%Y')}."
        next false
      end
      @roles[mapa.id] = role
      true
    end
  end

  def values(mapa)
    role = @roles.fetch(mapa.id)
    @values[mapa.id] ||= service(role.cargo).values(mapa).merge(role_id: role.id)
  end

  def groups
    @groups ||= maps.group_by { |mapa| @roles.fetch(mapa.id).cargo }.transform_values do |records|
      service(@roles.fetch(records.first.id).cargo).totals(records)
    end
  end

  def totals
    @totals ||= begin
      result = service('motorista').totals([])
      groups.each_value do |group|
        group.each { |key, value| result[key] += value unless key == :percentual_devolucao }
      end
      result[:percentual_devolucao] = result[:pdv_real] + result[:devolucoes] == 0 ? 0 : result[:devolucoes] / (result[:pdv_real] + result[:devolucoes])
      result
    end
  end

  def validate!
    raise EmployeeRole::HistoryError, issues.join(' ') if issues.any?
  end

  def service(cargo)
    @services[cargo] ||= MapaRemuneracaoService.new(cargo)
  end

  def snapshot
    {
      employee: employee.attributes.slice('id', 'nome', 'matricula', 'cpf'),
      totals: totals, groups: groups, issues: issues,
      roles: @roles.values.uniq.map(&:attributes),
      maps: maps.map { |mapa| { source: mapa.attributes, calculation: values(mapa) } },
      rule: 'Bônus apurado separadamente por cargo; van recebe caixas e entregas mesmo em recarga. Tarifa do bônus na última data de mapa do cargo.'
    }
  end
end
