class AiActionRequest < ApplicationRecord
  class Conflict < StandardError; end
  class ConfirmationRequired < StandardError; end

  belongs_to :user
  belongs_to :ai_conversation
  belongs_to :ai_message, optional: true

  validates :kind, inclusion: { in: %w[create_task create_plan update_task] }
  validates :status, inclusion: { in: %w[pending executed cancelled] }
  validates :confirmation_token, :expires_at, presence: true
  validate :same_account

  before_validation :set_confirmation, on: :create
  attr_readonly :user_id, :ai_conversation_id, :kind, :payload, :preview, :confirmation_token, :expires_at

  scope :pending, -> { where(status: "pending") }
  after_update_commit :broadcast_created_tasks, if: -> { saved_change_to_status? && status == "executed" }

  def confirm!(token)
    ai_conversation.with_lock do
      with_lock do
        verify_confirmation!(token)
        return result if status == "executed"
        raise Conflict, "Esta ação foi cancelada. Peça uma nova proposta ao assistente." unless status == "pending"
        raise Conflict, "Esta proposta expirou. Peça uma nova proposta ao assistente." if expires_at <= Time.current
        raise Conflict, "Aguarde a resposta em andamento antes de confirmar." if ai_conversation.processing?

        if kind == "update_task"
          task = Task.accessible_to(user.reload).find_by(id: payload.fetch("task_id"))
          raise AiAssistant::ActionDraft::Forbidden, "Tarefa não encontrada ou sem acesso para alteração." unless task
          task.with_lock { execute_draft! }
        else
          execute_draft!
        end
        result
      end
    end
  end

  def cancel!
    ai_conversation.with_lock do
      with_lock do
        raise Conflict, "Esta ação já foi executada e não pode ser cancelada aqui." if status == "executed"
        update!(status: "cancelled", cancelled_at: Time.current) if status == "pending"
      end
    end
  end

  def client_json
    routes = Rails.application.routes.url_helpers
    effective_status = status == "pending" && expires_at <= Time.current ? "expired" : status
    { id: id, kind: kind, status: effective_status, preview: preview, result: result,
      expires_at: expires_at.iso8601, executed_at: executed_at&.iso8601,
      confirmation_token: effective_status == "pending" ? confirmation_token : nil,
      confirm_path: routes.confirm_ai_assistant_action_path(self), cancel_path: routes.cancel_ai_assistant_action_path(self) }
  end

  private

  def broadcast_created_tasks
    ids = kind == "create_task" ? [result["id"]] : result.fetch("task_ids", [])
    Task.where(id: ids, creator_id: user_id).includes(:bucket).find_each do |task|
      task.broadcast_new_task(task) unless task.inbox?
    end
  end

  def verify_confirmation!(token)
    unless token.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(confirmation_token, token)
      raise ConfirmationRequired, "Confira a prévia e use o botão de confirmação."
    end
  end

  def set_confirmation
    self.confirmation_token ||= SecureRandom.hex(32)
    self.expires_at ||= 30.minutes.from_now
  end

  def same_account
    errors.add(:user, "deve ser o dono da conversa") if ai_conversation && ai_conversation.user_id != user_id
    errors.add(:ai_message, "deve pertencer à conversa") if ai_message && ai_message.ai_conversation_id != ai_conversation_id
  end

  def execute_draft!
    draft = AiAssistant::ActionDraft.restore(user: user.reload, kind: kind, payload: payload)
    unless draft.preview == preview
      raise Conflict, "Os dados ou acessos mudaram desde a prévia. Peça uma nova proposta antes de confirmar."
    end
    outcome = draft.execute!(request_id: id)
    update!(status: "executed", executed_at: Time.current, result: outcome)
  end
end
