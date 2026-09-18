require "test_helper"

class MeetingMinutesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:one) }

  test "lista as atas do action plan" do
    get action_plan_meeting_minutes_url(action_plans(:one))

    assert_response :success
    assert_select "h1", /Atas de reunião/
    assert_select ".meeting-minute-index-empty"
  end

  test "mostra edição recolhida e histórico no offcanvas quando há edição" do
    meeting = MeetingMinute.new(
      action_plan: action_plans(:one),
      creator: users(:one),
      title: "Reunião com histórico",
      meeting_date: Date.current,
      status: :completed,
      decisions: ["Decisão atual"],
      original_decisions: ["Decisão original"]
    )
    meeting.save!(validate: false)
    meeting.edits.create!(user: users(:one), changes_snapshot: {
      "before" => { "decisions" => ["Decisão original"], "pending_items" => [] },
      "after" => { "decisions" => ["Decisão atual"], "pending_items" => [] }
    })

    get action_plan_meeting_minute_url(action_plans(:one), meeting)

    assert_response :success
    assert_select "[data-meeting-minute-toggle-target='editor']", count: 3
    assert_select "button[data-action='meeting-minute-toggle#cancel']", count: 3
    assert_select "button[data-action='meeting-minute-toggle#edit']", count: 3
    assert_select "#meeting-minute-history.offcanvas"
    assert_select "[data-meeting-minute-toggle-target='original']"
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

  test "permite ao criador editar decisões e pendências e registra o histórico" do
    meeting = MeetingMinute.new(
      action_plan: action_plans(:one),
      creator: users(:one),
      title: "Reunião editável",
      meeting_date: Date.current,
      status: :completed,
      summary: "Resumo original",
      original_summary: "Resumo original",
      decisions: ["Decisão original"],
      pending_items: ["Pendência original"],
      original_decisions: ["Decisão original"],
      original_pending_items: ["Pendência original"]
    )
    meeting.save!(validate: false)

    patch update_content_action_plan_meeting_minute_url(action_plans(:one), meeting), params: {
      meeting_minute: {
        summary: "Resumo revisado",
        decisions: ["Decisão revisada"],
        pending_items: ["Pendência revisada"]
      }
    }

    assert_redirected_to action_plan_meeting_minute_path(action_plans(:one), meeting)
    meeting.reload
    assert_equal ["Decisão revisada"], meeting.decisions
    assert_equal ["Pendência revisada"], meeting.pending_items
    assert_equal "Resumo revisado", meeting.summary
    assert_equal "Resumo original", meeting.original_summary
    assert_equal ["Decisão original"], meeting.original_decisions
    assert_equal users(:one), meeting.edits.last.user
    assert_equal "Decisão original", meeting.edits.last.changes_snapshot.dig("before", "decisions").first
  end

  test "não permite que um usuário sem colaboração edite a ata" do
    meeting = MeetingMinute.new(
      action_plan: action_plans(:one),
      creator: users(:one),
      title: "Reunião protegida",
      meeting_date: Date.current,
      status: :completed,
      decisions: ["Decisão original"]
    )
    meeting.save!(validate: false)
    sign_out users(:one)
    sign_in users(:two)

    patch update_content_action_plan_meeting_minute_url(action_plans(:one), meeting), params: {
      meeting_minute: { decisions: ["Alteração indevida"], pending_items: [] }
    }

    assert_redirected_to action_plans_path
    assert_equal ["Decisão original"], meeting.reload.decisions
    assert_empty meeting.edits
  end
end
