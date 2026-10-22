module Employees
  class HistoricalRegistration
    include ActiveModel::Model
    include ActiveModel::Attributes

    PROFILES = {
      'du_motorista' => ['Motorista · DU', 'du', 'motorista'],
      'du_van' => ['Motorista de van · DU', 'du', 'van'],
      'du_ajudante' => ['Ajudante · DU', 'du', 'ajudante'],
      'az_ajudante' => ['Ajudante · AZ', 'az', 'ajudante'],
      'az_operador' => ['Operador de empilhadeira · AZ', 'az', 'operador']
    }.freeze

    attribute :nome, :string
    attribute :matricula, :string
    attribute :profile, :string
    attribute :starts_on, :string
    attribute :ends_on, :string
    attr_reader :employee

    validates :nome, presence: true
    validates :profile, inclusion: { in: PROFILES.keys }
    validate :valid_dates
    validate :known_identity

    def save(user:)
      self.nome = nome.to_s.squish
      self.matricula = matricula.to_s.strip.presence
      return false unless valid?
      _, sector, cargo = PROFILES.fetch(profile)
      unless user.can_manage_employees? && user.employee_sectors.include?(sector)
        errors.add(:base, 'Você não pode cadastrar colaboradores deste setor.')
        return false
      end

      Employee.transaction do
        Employee.connection.execute('SELECT pg_advisory_xact_lock(739231200)')
        next false unless valid?
        @employee = Employee.create!(nome: nome, matricula: matricula, historical_only: true, active: false, retired_at: @parsed_dates[:ends_on])
        role = @employee.employee_roles.create!(sector: sector, cargo: cargo, legacy: true,
          starts_on: @parsed_dates[:starts_on], ends_on: @parsed_dates[:ends_on], created_by: user, reason: 'Cadastro histórico de ex-colaborador para rastreio de checklist')
        @employee.employee_career_events.create!(user: user, details: {
          action: 'historical_registration', role: role.attributes,
          reason: 'Ex-colaborador sem cadastro anterior no app; datas não informadas permanecem desconhecidas.'
        })
        true
      end
    rescue ActiveRecord::RecordInvalid => error
      errors.add(:base, error.record.errors.full_messages.to_sentence)
      false
    end

    private

    def valid_dates
      @parsed_dates = %i[starts_on ends_on].to_h do |field|
        raw = public_send(field)
        [field, raw.present? ? Date.iso8601(raw) : nil]
      rescue ArgumentError
        errors.add(:base, 'Informe datas válidas.')
        [field, nil]
      end
      first, last = @parsed_dates.values_at(:starts_on, :ends_on)
      errors.add(:base, 'O fim na função não pode ser anterior ao início.') if first && last && last < first
      errors.add(:base, 'As datas do cadastro histórico não podem estar no futuro.') if [first, last].compact.any? { |date| date > Date.current }
    end

    def known_identity
      if matricula.present? && Employee.where(matricula: matricula).exists?
        errors.add(:base, 'Esta matrícula já possui cadastro. Selecione a pessoa existente, inclusive entre os inativos.')
      elsif nome.present?
        owners = EmployeeName.where(normalized_name: EmployeeName.normalize(nome)).select(:employee_id)
        if owners.exists? && (matricula.blank? || Employee.where(id: owners, matricula: [nil, matricula]).exists?)
          errors.add(:base, 'Já existe um cadastro com este nome. Confira os colaboradores inativos; em caso de homônimos, informe uma matrícula diferente.')
        end
      end
    end
  end
end
