module AiAssistantsHelper
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
    suggestions
  end
end
