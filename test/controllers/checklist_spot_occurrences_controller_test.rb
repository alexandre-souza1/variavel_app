require "test_helper"

class ChecklistSpotOccurrencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @task = tasks(:one)
    @task.update!(title: "Aplicar matriz ao SPOT IZI3B97 por não realização do Checklist de Saída no dia 29/04/2026", description: nil)
    @task.labels << @task.bucket.action_plan.labels.create!(name: "SPOT", color: "#ee7214")
    @attributes = { spot_plate: "IZI3B97", occurred_on: "2026-04-29", checklist_kind: "saida" }
  end

  test "spot review is separate from employees and one batch creates plate occurrences" do
    get checklist_occurrences_path(year: 2026, display: "review")
    assert_select ".checklist-tracking__candidate", count: 0
    get checklist_occurrences_path(year: 2026, display: "review", subject: "spot")
    assert_response :success
    assert_select ".checklist-tracking__candidate summary .task-label-badge", text: "SPOT"
    assert_select "input[name='checklist_occurrence[spot_plate]'][value='IZI3B97']"
    assert_select "select[name='checklist_occurrence[employee_id]']", count: 0
    assert_select "select[name=employee_sector]", count: 0
    assert_select "select[name='checklist_occurrence[checklist_kind]'] option[selected][value=saida]"
    assert_difference("ChecklistOccurrence.count", 1) do
      post identify_checklist_occurrences_path, params: { year: 2026, subject: "spot", display: "review" }
    end
    assert_redirected_to checklist_occurrences_path(year: 2026, subject: "spot", display: "review")
    follow_redirect!
    assert_select ".checklist-tracking__candidate", count: 0
    get checklist_occurrences_path(year: 2026, subject: "spot")
    assert_select ".checklist-tracking__ranking tbody tr", count: 1
    assert_select ".checklist-tracking__ranking tbody td:first-child", text: /IZI3B97/
    assert_select "#tracking-navigation a", count: 4 do |links|
      links.each { |link| assert_equal "spot", Rack::Utils.parse_query(URI.parse(link['href']).query)['subject'] }
    end
    get checklist_occurrences_path(year: 2026)
    assert_select ".checklist-tracking__ranking tbody tr", count: 0
  end

  test "spot calendar and modal group duplicate tasks and exclusions refresh the plate history" do
    first = @task.checklist_occurrences.create!(@attributes.merge(recorded_by: @user))
    duplicate_task = @task.bucket.tasks.create!(title: "Outra ação do SPOT", creator: @user)
    duplicate = duplicate_task.checklist_occurrences.create!(@attributes.merge(recorded_by: @user))
    duplicate_task.checklist_occurrences.create!(@attributes.merge(spot_plate: "DLL4A97", recorded_by: @user))
    get checklist_occurrences_path(year: 2026, subject: "spot", display: "calendar", month: 4)
    assert_response :success
    assert_select "[data-calendar-date='2026-04-29'] .checklist-tracking__day-count", text: /2/
    assert_select "[data-calendar-date='2026-04-29'] .checklist-tracking__day-people", text: /IZI3B97/
    assert_select ".checklist-tracking__calendar-navigation a[aria-label='Próximo mês']" do |links|
      assert_equal 'spot', Rack::Utils.parse_query(URI.parse(links.first['href']).query)['subject']
    end
    get details_checklist_occurrences_path(year: 2026, subject: "spot", spot_plate: "izi-3b97", month: 4)
    assert_select ".checklist-tracking__modal-event", count: 1
    assert_select ".checklist-tracking__source", count: 2
    assert_select ".task-label-badge", text: "SPOT"
    assert_not_includes response.body, "DLL4A97"
    patch exclude_checklist_occurrence_path(first), params: { subject: "spot", exclusion: { reason: "network_error", details: "Sem conexão no SPOT" } }, as: :json
    assert_response :success
    assert duplicate.reload.cancelled_at?
    get checklist_occurrences_path(year: 2026, subject: "spot", display: "history", spot_plate: "IZI3B97")
    assert_select ".checklist-tracking__event", count: 0
    assert_select ".checklist-tracking__history-actions a", text: "Desconsideradas (1)"
    get details_checklist_occurrences_path(year: 2026, subject: "spot", spot_plate: "IZI3B97", status: "excluded")
    assert_select ".checklist-tracking__modal-event.is-excluded", count: 1
    assert_select ".checklist-tracking__justification", text: /Sem conexão no SPOT/, count: 2
  end

  test "manual SPOT registration and cancellation render in the task panel without an employee" do
    assert_difference("ChecklistOccurrence.count", 1) do
      post task_checklist_occurrences_path(@task), params: { subject: "spot", checklist_occurrence: @attributes }, as: :turbo_stream
    end
    assert_response :success
    assert_select ".checklist-tracking__record strong", text: "SPOT IZI3B97"
    record = @task.checklist_occurrences.last
    patch cancel_task_checklist_occurrence_path(@task, record), params: { subject: "spot", cancellation_reason: "Placa incorreta" }, as: :turbo_stream
    assert_response :success
    assert record.reload.cancelled_at?
    assert_select ".checklist-tracking__record", text: /Placa incorreta/
  end

  test "one SPOT exclusion response updates the calendar and preserves the selected plate" do
    record = @task.checklist_occurrences.create!(@attributes.merge(recorded_by: @user))
    @task.checklist_occurrences.create!(@attributes.merge(spot_plate: "DLL4A97", recorded_by: @user))
    filters = { year: 2026, subject: "spot", month: 4 }
    patch exclude_checklist_occurrence_path(record), params: {
      subject: "spot", exclusion: { reason: "network_error", details: "Sem conexão" },
      dashboard: filters.merge(display: "calendar"), modal: filters.merge(spot_plate: "IZI3B97")
    }, as: :json
    assert_response :success
    result = response.parsed_body
    calendar = Nokogiri::HTML.fragment(result.fetch("fragments").fetch("tracking-overview"))
    day = calendar.at_css("[data-calendar-date='2026-04-29']")
    assert_equal "1 faltas", day.at_css(".checklist-tracking__day-count").text.strip
    assert_includes day.text, "DLL4A97"
    assert_not_includes day.text, "IZI3B97"
    modal = Nokogiri::HTML.fragment(result.fetch("modal"))
    assert_equal 1, modal.css(".checklist-tracking__modal-event.is-excluded").size
    assert_includes modal.text, "IZI3B97"
    assert_not_includes modal.text, "DLL4A97"
  end

  test "private SPOT plates are absent from totals filters history and exclusion access" do
    outsider = users(:two)
    outsider.update!(role: :user, sector: :warehouse)
    private_plan = outsider.action_plans.create!(name: "Plano SPOT reservado", public: false, sector: :warehouse)
    task = private_plan.buckets.first.tasks.create!(title: "SPOT secreto", creator: outsider)
    record = task.checklist_occurrences.create!(@attributes.merge(spot_plate: "ABC1234", recorded_by: outsider))
    @user.update!(role: :user, sector: :fleet)
    sign_in @user
    get checklist_occurrences_path(year: 2026, subject: "spot")
    assert_response :success
    assert_not_includes response.body, "ABC1234"
    get details_checklist_occurrences_path(year: 2026, subject: "spot", spot_plate: "ABC1234")
    assert_select ".checklist-tracking__modal-event", count: 0
    patch exclude_checklist_occurrence_path(record), params: { subject: "spot", exclusion: { reason: "turned_map" } }, as: :json
    assert_response :not_found
    assert_nil record.reload.cancelled_at
  end
end
