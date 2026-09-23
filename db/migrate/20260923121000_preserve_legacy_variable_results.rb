require 'bigdecimal'

class PreserveLegacyVariableResults < ActiveRecord::Migration[7.1]
  class Closing < ActiveRecord::Base
    self.table_name = 'variable_closings'
  end

  def up
    change_column_null :variable_closings, :user_id, true
    add_column :variable_closings, :legacy_baseline, :boolean, default: false, null: false
    Closing.reset_column_information
    # Snapshot the pre-change preview, not a claim that payroll was paid.
    # This implementation is intentionally self-contained: future business rules
    # must not change what this migration records when deployed later.
    say_with_time 'Preservando prévias legadas dos períodos encerrados' do
      suppress_messages do
        @rates = select_all('SELECT * FROM calculation_rate_versions WHERE effective_on IS NULL ORDER BY id').to_a.index_by { |row| [row['categoria'], row['nome']] }
        maps = select_all('SELECT * FROM mapas').to_a
        people = select_all('SELECT * FROM employees').to_a.index_by { |row| row['id'] }
        roles = select_all('SELECT * FROM employee_roles').to_a
        roles.each do |role|
          matching = maps.select do |mapa|
            codes = role['cargo'] == 'ajudante' ? [mapa['matric_ajudante'], mapa['matric_ajudante_2']] : [mapa['matric_motorista']]
            codes.include?(role['promax']) && date_for(mapa['data'])
          end
          matching.group_by { |mapa| closing_date(date_for(mapa['data'])) }.each do |finish, records|
            next unless finish < Date.current
            calculations = records.map { |mapa| { source: mapa, calculation: values(mapa, role) } }
            totals = totals_for(records, calculations, role['cargo'])
            Closing.create!(employee_id: role['employee_id'], year: finish.year, month: finish.month, revision: 1,
              legacy_baseline: true, reason: 'Referência da prévia legada anterior à implantação. Não comprova pagamento. Revisões devem ser registradas pelo RH.',
              result: { employee: people[role['employee_id']].slice('id', 'nome', 'matricula', 'cpf'), roles: [role], maps: calculations,
                        totals: totals, groups: { role['cargo'] => totals }, issues: [], rule: 'Prévia legada: regra e parâmetros disponíveis na implantação; não reconstrói tarifas históricas desconhecidas.' })
          end
        end
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'As referências históricas devem ser preservadas.'
  end

  private

  def date_for(value)
    digits = value.to_s.gsub(/\D/, '')
    case digits.length
    when 8 then Date.new(digits[4..7].to_i, digits[2..3].to_i, digits[0..1].to_i)
    when 7 then Date.new(digits[3..6].to_i, digits[1..2].to_i, digits[0].to_i)
    when 6 then Date.new(digits[2..5].to_i, digits[1].to_i, digits[0].to_i)
    end
  rescue Date::Error
    nil
  end

  def closing_date(date)
    month = date.day >= 21 ? date.next_month : date
    Date.new(month.year, month.month, 20)
  end

  def decimal(value)
    BigDecimal(value.to_s.presence || '0')
  end

  def rate(cargo, name)
    decimal(@rates[[cargo, name]]&.fetch('valor'))
  end

  def values(mapa, role)
    cargo = role['cargo']
    multiplier = if mapa['fator'].to_f == 2
      BigDecimal('0.5')
    elsif cargo == 'motorista' && mapa['fator'].to_f == 0 && decimal(mapa['pdv_total']) >= 2
      2
    else
      1
    end
    cx = decimal(mapa['cx_real']) * rate(cargo, 'valor_caixa') * multiplier
    pdv = decimal(mapa['pdv_real']) * rate(cargo, 'valor_entrega') * multiplier
    rec = mapa['recarga'] == 'SIM' ? rate(cargo, 'valor_recarga') : 0
    { valor_cx: cx, valor_pdv: pdv, valor_rec: rec, valor_mp: mapa['recarga'] == 'SIM' ? rec : cx + pdv,
      categoria: cargo, role_id: role['id'], recarga: mapa['recarga'] == 'SIM', recarga_inconsistente: false,
      tarifas: { caixa: rate(cargo, 'valor_caixa'), entrega: rate(cargo, 'valor_entrega'), recarga: rate(cargo, 'valor_recarga') } }
  end

  def totals_for(records, calculations, cargo)
    normal = records.reject { |mapa| mapa['recarga'] == 'SIM' }
    cx = normal.sum { |mapa| decimal(mapa['cx_real']) }
    pdv = normal.sum { |mapa| decimal(mapa['pdv_real']) }
    pdv_total = normal.sum { |mapa| decimal(mapa['pdv_total']) }
    devolucoes = pdv_total - pdv
    percentage = pdv_total.zero? ? 0 : devolucoes / pdv_total
    bonus = cargo != 'van' && records.size >= 15 && percentage <= BigDecimal('0.03') ? rate('geral', 'bonus_devolucao') : 0
    vals = calculations.map { |entry| entry[:calculation] }
    { cx_real: cx, pdv_real: pdv, recargas: cargo == 'van' ? 0 : records.size - normal.size,
      devolucoes: devolucoes, percentual_devolucao: percentage, bonus_devolucao: bonus,
      valor_total: vals.sum { |v| v[:valor_mp] } + bonus,
      valor_caixas: vals.sum { |v| v[:recarga] ? 0 : v[:valor_cx] }, valor_pdvs: vals.sum { |v| v[:recarga] ? 0 : v[:valor_pdv] },
      valor_recargas: cargo == 'van' ? 0 : vals.sum { |v| v[:valor_rec] }, quantidade_mapas: records.size, total_mapas: records.size }
  end
end
