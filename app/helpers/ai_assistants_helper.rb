module AiAssistantsHelper
  def ai_assistant_page_context
    reference = if @task_to_open&.persisted?
                  { type: "task", id: @task_to_open.id }
                elsif controller_name == "action_plans" && action_name == "show" && @action_plan&.persisted?
                  { type: "plan", id: @action_plan.id }
                elsif controller_name == "plates" && action_name == "show" && @plate&.persisted?
                  { type: "plate", id: @plate.id }
                end
    AiAssistant::PageContext.new(user: current_user, reference: reference).client_data
  rescue AiAssistant::PageContext::Unavailable
    {}
  end

  def ai_assistant_suggestions(user)
    access = AiAssistant::Access.new(user)
    suggestions = ['O que tenho para o dia de hoje?']
    suggestions << if user.admin?
                     'Como está o consumo de IA nos últimos 7 dias?'
                   elsif access.allowed?(:az)
                     'Resuma os indicadores do Armazém neste fechamento.'
                   elsif access.allowed?(:finance)
                     'Quais foram os gastos do meu setor neste mês?'
                   elsif access.allowed?(:du)
                     'Resuma os indicadores de DU neste fechamento.'
                   else
                     'Quais planos de ação posso consultar?'
                   end
    suggestions << 'O que posso consultar com meu perfil?'
    suggestions << 'Quero criar uma tarefa.' if AiAssistant::ActionDraft.allowed?(user)
    suggestions << 'Quero atualizar uma tarefa.' if AiAssistant::ActionDraft.allowed?(user, kind: "update_task")
    suggestions
  end
end
