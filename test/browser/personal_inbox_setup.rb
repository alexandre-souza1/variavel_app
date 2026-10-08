raise "Somente banco de testes" unless Rails.env.test?

owner = User.find_or_initialize_by(email: "browser-inbox-owner@example.test")
owner.update!(name: "Browser Inbox Owner", password: "password", password_confirmation: "password", role: :admin, sector: :fleet)
other = User.find_or_initialize_by(email: "browser-inbox-other@example.test")
other.update!(name: "Browser Inbox Other", password: "password", password_confirmation: "password", role: :user, sector: :fleet)
plans = %w[A B].map { |name| owner.action_plans.find_or_create_by!(name: "Browser Inbox #{name}") }
owner.personal_inbox!.tasks.destroy_all
plans.each { |plan| plan.buckets.each { |bucket| bucket.tasks.destroy_all } }
other.personal_inbox!.tasks.find_or_create_by!(title: "Segredo Browser Inbox", creator: other)

Rails.root.join("tmp/browser").mkpath
Rails.root.join("tmp/browser/personal_inbox_setup.json").write({
  plans: plans.map { |plan| { id: plan.id, bucket_id: plan.buckets.work.first.id } },
  inbox_id: owner.personal_inbox!.id
}.to_json)
