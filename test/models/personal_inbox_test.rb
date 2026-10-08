require "test_helper"
require "minitest/mock"

class PersonalInboxModelTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(name: "Criador")
    users(:two).update!(name: "Responsável")
    @inbox = @user.personal_inbox!
  end

  test "there is exactly one personal inbox per user and ownership cannot mix with a plan" do
    assert_equal @inbox, User.find(@user.id).personal_inbox!
    duplicate = Bucket.new(user: @user, inbox: true, name: "Outra Entrada")
    assert_not duplicate.valid?
    assert_not Bucket.new(action_plan: action_plans(:one), inbox: true, name: "Entrada do plano").valid?
    assert_not @inbox.update(action_plan: action_plans(:one))
  end

  test "a task cannot belong to another user's inbox even through the model" do
    task = @inbox.tasks.build(title: "Criador incorreto", creator: users(:two))
    assert_not task.save
    assert_includes task.errors[:bucket], "deve ser a Entrada do criador da tarefa"
  end

  test "the database also rejects mixed ownership and duplicate inbox owners" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Bucket.transaction(requires_new: true) { @inbox.update_columns(action_plan_id: action_plans(:one).id) }
    end
    assert_nil @inbox.reload.action_plan_id
    assert_raises(ActiveRecord::RecordNotUnique) do
      Bucket.transaction(requires_new: true) do
        Bucket.insert_all!([{ name: "Duplicada", inbox: true, user_id: @user.id }])
      end
    end
    assert_equal 1, Bucket.where(inbox: true, user: @user).count
  end

  test "private tasks are invisible to assignees and administrators" do
    task = users(:two).personal_inbox!.tasks.create!(title: "Privada", creator: users(:two), users: [@user])
    assert_not Task.visible_for(@user).exists?(task.id)
    assert_not Task.accessible_to(@user).exists?(task.id)
    assert Task.accessible_to(users(:two)).exists?(task.id)
  end

  test "validating or rejecting a move does not erase the original plan labels" do
    task = tasks(:one)
    label_ids = task.label_ids
    assert_not_empty label_ids
    task.assign_attributes(bucket: @inbox, title: "")
    assert_not task.valid?
    assert_equal label_ids, Task.find(task.id).label_ids
    assert_not task.save
    assert_equal label_ids, Task.find(task.id).label_ids
    assert_equal buckets(:one).id, Task.find(task.id).bucket_id
  end

  test "inbox recurrence preserves owner checklist and plan independence" do
    task = @inbox.tasks.create!(title: "Repetir rascunho", creator: @user, due_at: 5.days.from_now,
      recurrence: "daily", clone_tasklist_on_recurrence: true)
    task.tasklist.tasklist_items.create!(content: "Revisar", completed: true)
    assert_difference("Task.count", 1) { task.update!(completed: true) }
    next_task = @inbox.tasks.find_by!(title: task.title, due_at: task.due_at + 1.day)
    assert_equal @user, next_task.creator
    assert_nil next_task.bucket.action_plan
    assert_equal ["Revisar"], next_task.tasklist.tasklist_items.pluck(:content)
    assert_not next_task.tasklist.tasklist_items.first.completed?
  end

  test "private due reminders go only to the creator and assignments notify when launched" do
    task = @inbox.tasks.create!(title: "Lembrar", creator: @user)
    assert_no_difference("Notification.count") { task.users << users(:two) }
    task.update_columns(due_at: 6.hours.from_now, due_notification_enabled: true)
    assert_difference("Notification.count", 1) { TaskDueNotificationService.notify_if_due_soon(task) }
    notice = Notification.order(:id).last
    assert_equal @user, notice.user
    assert_equal "/inbox?task_id=#{task.id}", notice.action_url
    assert_difference("Notification.count", 1) { task.update!(bucket: buckets(:one)) }
    assert_equal users(:two), Notification.order(:id).last.user
  end

  test "updates and movement broadcast only to the owner inbox and the actual plan" do
    task = @inbox.tasks.create!(title: "Privada", creator: @user)
    streams = []
    broadcaster = ->(stream, **_options) { streams << stream }
    Turbo::StreamsChannel.stub(:broadcast_remove_to, broadcaster) do
      Turbo::StreamsChannel.stub(:broadcast_prepend_to, broadcaster) do
        Turbo::StreamsChannel.stub(:broadcast_update_to, broadcaster) do
          task.update!(title: "Privada atualizada")
          assert_equal ["tasks_inbox_#{@user.id}"], streams.uniq
          streams.clear
          old_feed = task.feed_stream
          task.update!(bucket: buckets(:one))
          assert_equal ["tasks_inbox_#{@user.id}", "tasks_action_plan_#{buckets(:one).action_plan_id}"].sort, streams.uniq.sort
          assert_not_equal old_feed, task.feed_stream
        end
      end
    end
  end
end
