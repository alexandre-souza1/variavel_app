raise "Use somente no ambiente de testes" unless Rails.env.test?

user = User.find_or_initialize_by(email: "browser-ai-actions@example.test")
user.assign_attributes(name: "Ana da Frota", password: "password", role: :user, sector: :fleet, active: true)
user.save!
user.ai_conversation&.destroy!
user.action_plans.where(name: ["Plano de inspeção", "Plano sugerido pela IA"]).destroy_all
plan = user.action_plans.create!(name: "Plano de inspeção", public: false)
conversation = AiConversation.create!(user: user, request_token: "browser-draft", requested_at: Time.current)
drafts = [
  AiAssistant::ActionDraft.new(user: user, kind: "create_task", arguments: {
    title: "Inspecionar pneus", description: '<img src=x onerror="window.aiInjected=true"> Conferir sulcos e calibragem.',
    plan_id: plan.id, bucket_id: plan.buckets.first.id, due_at: "2030-10-20T14:00:00-03:00",
    reminder: true, checklist: ["Eixo dianteiro", "Eixo traseiro"]
  }),
  AiAssistant::ActionDraft.new(user: user, kind: "create_plan", arguments: {
    name: "Plano sugerido pela IA", description: "Inspeções da equipe para o próximo mês.",
    tasks: [{ title: "Conferir pressão", due_at: "2030-10-20" }, { title: "Revisar estepe", checklist: ["Verificar fixação"] }]
  })
]
conversation.finish!("browser-draft", answer: { content: "Confira as duas propostas. A criação acontece após sua confirmação.", sources: [], actions: drafts.map(&:to_h) })
FileUtils.mkdir_p(Rails.root.join("tmp/browser"))
File.write(Rails.root.join("tmp/browser/ai_assistant_actions_setup.json"), { plan_id: plan.id, user_id: user.id }.to_json)
puts "Dados de teste do assistente preparados."
