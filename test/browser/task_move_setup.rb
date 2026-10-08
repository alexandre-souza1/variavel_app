load Rails.root.join("test/browser/personal_inbox_setup.rb")
owner = User.find_by!(email: "browser-inbox-owner@example.test")
plan = owner.action_plans.find_by!(name: "Browser Inbox A")
source, destination = plan.buckets.work.order(:position).first(2)
moving = source.tasks.create!(title: "Cartão em movimento", creator: owner)
destination.tasks.create!(title: "Já concluída", creator: owner, completed: true)
first = destination.tasks.create!(title: "Primeira aberta", creator: owner)
last = destination.tasks.create!(title: "Última aberta", creator: owner)
draft = owner.personal_inbox!.tasks.create!(title: "Rascunho privado", creator: owner)
Rails.root.join("tmp/browser/task_move_setup.json").write({
  plan_id: plan.id, source_id: source.id, destination_id: destination.id,
  inbox_id: owner.personal_inbox!.id, moving_id: moving.id,
  first_id: first.id, last_id: last.id, draft_id: draft.id
}.to_json)
