require "test_helper"

class MeetingMinutesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:one) }

  test "lista as atas do action plan" do
    get action_plan_meeting_minutes_url(action_plans(:one))

    assert_response :success
    assert_select "h1", /Atas de reunião/
    assert_select ".meeting-minute-index-empty"
  end

  test "gera PDF da ata com tabela de assinaturas quando há participantes" do
    meeting = MeetingMinute.new(
      action_plan: action_plans(:one),
      creator: users(:one),
      title: "Reunião de teste",
      meeting_date: Date.current,
      status: :completed,
      summary: "Resumo da reunião",
      participants: ["Ana", "Bruno"]
    )
    meeting.save!(validate: false)

    get action_plan_meeting_minute_url(action_plans(:one), meeting, format: :pdf, download: true)

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_match "%PDF", response.body
    assert_includes response.headers["Content-Disposition"], "attachment"
  end

  test "atualiza participantes depois da criação da ata" do
    meeting = MeetingMinute.new(
      action_plan: action_plans(:one),
      creator: users(:one),
      title: "Reunião de teste",
      meeting_date: Date.current,
      status: :completed
    )
    meeting.save!(validate: false)

    patch update_participants_action_plan_meeting_minute_url(action_plans(:one), meeting),
      params: { meeting_minute: { participants: "Ana Souza\nBruno Lima\nAna Souza" } }

    assert_redirected_to action_plan_meeting_minute_path(action_plans(:one), meeting)
    assert_equal ["Ana Souza", "Bruno Lima"], meeting.reload.participants
  end

  test "cria tarefas sugeridas uma única vez e adiciona label da ata" do
    meeting = MeetingMinute.new(
      action_plan: action_plans(:one),
      creator: users(:one),
      title: "Reunião de teste",
      meeting_date: Date.current,
      status: :completed,
      tasks_suggestions: [{ "title" => "Tarefa da ata", "description" => "Descrição" }]
    )
    meeting.save!(validate: false)
    bucket = action_plans(:one).buckets.first

    post create_tasks_action_plan_meeting_minute_url(action_plans(:one), meeting),
      params: { suggestion_ids: [0], bucket_ids: { "0" => bucket.id } }

    assert_redirected_to action_plan_meeting_minute_path(action_plans(:one), meeting)
    assert meeting.reload.tasks_created?
    task = bucket.tasks.order(:created_at).last
    assert_includes task.labels.pluck(:name), "Ata de Reunião"

    assert_no_difference "Task.count" do
      post create_tasks_action_plan_meeting_minute_url(action_plans(:one), meeting),
        params: { suggestion_ids: [0], bucket_ids: { "0" => bucket.id } }
    end
  end
end
