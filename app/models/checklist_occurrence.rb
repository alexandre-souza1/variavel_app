# A confirmed missed checklist reported by an action, independent of Checklist.
class ChecklistOccurrence < ApplicationRecord
  KINDS = { "saida" => "Saída", "retorno" => "Retorno", "empilhadeira" => "Empilhadeira",
            "paleteira" => "Paleteira", "seguranca" => "Segurança", "outro" => "Outro" }.freeze

  EXCLUSION_REASONS = { "execution_error" => "Erro na execução", "turned_map" => "Mapa virado",
                        "network_error" => "Erro de rede", "other" => "Outro motivo" }.freeze

  before_validation { self.spot_plate = self.class.normalize_spot_plate(spot_plate).presence }
  before_validation :inherit_justified_exclusion, on: :create
  validates :exclusion_category, inclusion: { in: EXCLUSION_REASONS.keys }, allow_nil: true

  belongs_to :task
  belongs_to :employee, optional: true
  belongs_to :recorded_by, class_name: "User"
  belongs_to :cancelled_by, class_name: "User", optional: true

  scope :spots, -> { where.not(spot_plate: nil) }
  scope :employees, -> { where(spot_plate: nil) }
  scope :active, -> { where(cancelled_at: nil) }
  scope :from_tracking_sources, -> do
    where(task_id: Task.joins(:bucket).where(buckets: { action_plan_id: ActionPlan.checklist_tracking_sources.select(:id) }).select(:id))
  end
  scope :visible_to, ->(user) do
    where(employee_id: Employee.for_checklist_tracking(user).select(:id))
      .or(where.not(spot_plate: nil).where(task_id: Task.accessible_to(user).select(:id)))
  end

  validates :spot_plate, format: { with: /\A[A-Z]{3}[0-9][A-Z0-9][0-9]{2}\z/ }, allow_nil: true
  validate :exactly_one_subject
  validates :spot_plate, uniqueness: { scope: [:task_id, :occurred_on, :checklist_kind],
    conditions: -> { active }, message: "já registrada nesta tarefa, data e tipo" }, if: -> { spot_plate.present? && cancelled_at.nil? }
  validates :occurred_on, presence: true
  validates :checklist_kind, inclusion: { in: KINDS.keys }
  validates :employee_id, uniqueness: { scope: [:task_id, :occurred_on, :checklist_kind],
    conditions: -> { active }, message: "já registrado nesta tarefa, data e tipo" }, if: -> { employee_id.present? && cancelled_at.nil? }
  validates :cancellation_reason, :cancelled_by, presence: true, if: :cancelled_at?
  validate :task_has_plan
  validate :role_allows_checklist, on: :create, unless: :cancelled_at?

  def self.normalize_spot_plate(value)
    value.to_s.upcase.delete(" -").strip
  end

  def spot? = spot_plate.present?
  def subject_name = spot? ? "SPOT #{spot_plate}" : employee.nome
  def subject_key = spot? ? ["spot", spot_plate] : ["employee", employee_id]
  def subject_attributes = spot? ? { spot_plate: spot_plate } : { employee_id: employee_id }

  def kind_label
    KINDS.fetch(checklist_kind)
  end

  def role_restriction_reason
    return if employee.nil? || occurred_on.nil? || !KINDS.key?(checklist_kind)
    ChecklistTracking::Eligibility.new(employee: employee, date: occurred_on).reason(checklist_kind)
  end

  private

  def exactly_one_subject
    errors.add(:base, "Informe um colaborador ou uma placa SPOT, sem misturar os dois.") unless employee_id.present? ^ spot_plate.present?
  end

  def role_allows_checklist
    reason = role_restriction_reason
    errors.add(:base, reason) if reason
  end

  def inherit_justified_exclusion
    return if cancelled_at? || (employee_id.blank? && spot_plate.blank?) || occurred_on.blank? || checklist_kind.blank?
    scope = self.class.where(subject_attributes).where(occurred_on: occurred_on, checklist_kind: checklist_kind)
    scope = scope.where(task_id: Task.accessible_to(recorded_by).select(:id)) if spot? && recorded_by
    previous = scope.where.not(exclusion_category: nil).where.not(cancelled_at: nil).order(:cancelled_at, :id).first
    return unless previous
    self.cancelled_at = previous.cancelled_at
    self.cancelled_by = previous.cancelled_by
    self.cancellation_reason = previous.cancellation_reason
    self.exclusion_category = previous.exclusion_category
  end

  def task_has_plan
    errors.add(:task, "deve pertencer a um plano de ação") if task&.inbox?
  end
end
