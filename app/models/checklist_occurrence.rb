# A confirmed missed checklist reported by an action, independent of Checklist.
class ChecklistOccurrence < ApplicationRecord
  KINDS = { "saida" => "Saída", "retorno" => "Retorno", "empilhadeira" => "Empilhadeira",
            "paleteira" => "Paleteira", "seguranca" => "Segurança", "outro" => "Outro" }.freeze

  EXCLUSION_REASONS = { "execution_error" => "Erro na execução", "turned_map" => "Mapa virado",
                        "network_error" => "Erro de rede", "other" => "Outro motivo" }.freeze

  before_validation :inherit_justified_exclusion, on: :create
  validates :exclusion_category, inclusion: { in: EXCLUSION_REASONS.keys }, allow_nil: true

  belongs_to :task
  belongs_to :employee
  belongs_to :recorded_by, class_name: "User"
  belongs_to :cancelled_by, class_name: "User", optional: true

  scope :active, -> { where(cancelled_at: nil) }
  scope :visible_to, ->(user) do
    where(employee_id: Employee.for_checklist_tracking(user).select(:id))
  end

  validates :occurred_on, presence: true
  validates :checklist_kind, inclusion: { in: KINDS.keys }
  validates :employee_id, uniqueness: { scope: [:task_id, :occurred_on, :checklist_kind],
    conditions: -> { active }, message: "já registrado nesta tarefa, data e tipo" }, if: -> { cancelled_at.nil? }
  validates :cancellation_reason, :cancelled_by, presence: true, if: :cancelled_at?
  validate :task_has_plan
  validate :role_allows_checklist, on: :create, unless: :cancelled_at?

  def kind_label
    KINDS.fetch(checklist_kind)
  end

  def role_restriction_reason
    return if employee.nil? || occurred_on.nil? || !KINDS.key?(checklist_kind)
    ChecklistTracking::Eligibility.new(employee: employee, date: occurred_on).reason(checklist_kind)
  end

  private

  def role_allows_checklist
    reason = role_restriction_reason
    errors.add(:base, reason) if reason
  end

  def inherit_justified_exclusion
    return if cancelled_at? || employee_id.blank? || occurred_on.blank? || checklist_kind.blank?
    previous = self.class.where(employee_id: employee_id, occurred_on: occurred_on, checklist_kind: checklist_kind)
      .where.not(exclusion_category: nil).where.not(cancelled_at: nil).order(:cancelled_at, :id).first
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
