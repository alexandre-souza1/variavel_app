# Prepare the module's existing browser data first, in the test database only.
abort "Use somente o banco de testes" unless Rails.env.test?
ids = JSON.parse(File.read(Rails.root.join("tmp/automations/browser.json")))
user = User.find(ids.fetch("user_id"))
conversation = AiConversation.create!(user: user, request_token: "browser-automations", requested_at: Time.current)
drafts = [
  AiAssistant::ActionDraft.build(user: user, kind: "create_automation", arguments: {
    name: "Combustível pela conversa", description: "Prévia segura <img src=x onerror='window.autoInjected=true'>",
    source_key: "invoices", operation: "sum", period: "month", filters: { budget_category_ids: [ids.fetch("budget_category_id"), ids.fetch("second_budget_category_id")] },
    action_key: "update_indicator", action_config: { routine_template_id: ids.fetch("template_id"), routine_indicator_id: ids.fetch("indicator_id") },
    schedule: "daily", execution_hour: 8
  }),
  AiAssistant::ActionDraft.build(user: user, kind: "create_automation", arguments: {
    name: "Aviso de pendências", source_key: "tasks", period: "today", filters: { status: "overdue", action_plan_id: ids.fetch("action_plan_id") },
    condition_operator: "gt", condition_value: 0, action_key: "notify", action_config: { title: "Há {{valor}} tarefas vencidas" },
    schedule: "hourly", activate: true
  })
]
conversation.finish!("browser-automations", answer: { content: "Confira as regras e confirme a que deseja salvar.", sources: [], actions: drafts.map(&:to_h) })
puts "Prévias de automação preparadas para o navegador de testes."
