raise "Use somente no ambiente de testes" unless Rails.env.test?

user = User.find_or_initialize_by(email: "browser-ai-updates@example.test")
user.assign_attributes(name: "Ana da Frota", password: "password", role: :user, sector: :fleet, active: true)
user.save!
user.ai_conversation&.destroy!
user.action_plans.where(name: ["Inspeção da frota", "Revisão da oficina"]).destroy_all
first = user.action_plans.create!(name: "Inspeção da frota", public: false)
second = user.action_plans.create!(name: "Revisão da oficina", public: false)
task = first.buckets.first.tasks.create!(title: "Inspecionar pneus", description: "Conferir sulcos", creator: user,
  due_at: "2030-10-20T14:00:00-03:00", user_ids: [user.id])
stale = first.buckets.first.tasks.create!(title: "Conferir estepe", creator: user, user_ids: [user.id])
conversation = AiConversation.create!(user: user, request_token: "browser-update", requested_at: Time.current)
drafts = [
  AiAssistant::ActionDraft.build(user: user, kind: "update_task", arguments: {
    task_id: task.id, changes: { due_at: "2030-10-21T15:00:00-03:00", reminder: true, completed: true,
      description: '<img src=x onerror="window.aiInjected=true"> Conferir sulcos e calibragem.' }
  }),
  AiAssistant::ActionDraft.build(user: user, kind: "update_task", arguments: { task_id: stale.id, changes: { title: "Revisar estepe" } })
]
conversation.finish!("browser-update", answer: { content: "Confira os valores anteriores e os novos antes de confirmar.", sources: [], actions: drafts.map(&:to_h) })
FileUtils.mkdir_p(Rails.root.join("tmp/browser"))
File.write(Rails.root.join("tmp/browser/ai_assistant_updates_setup.json"), {
  plan_id: first.id, other_plan_id: second.id, task_id: task.id, stale_task_id: stale.id, user_id: user.id
}.to_json)
puts "Dados de teste de alterações e contexto preparados."
