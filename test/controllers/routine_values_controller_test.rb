require "test_helper"

class RoutineValuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    plan = @user.action_plans.create!(name: "Grade de despesas", sector: @user.sector)
    template = Routines::PlanTemplateBuilder.call(action_plan: plan, attributes: { name: "Despesas" })
    @indicator = template.routine_categories.first.routine_indicators.create!(
      name: "Combustível", position: 0, value_type: :currency,
      calculation_type: :plus, goal_direction: :less_or_equal
    )
    @routine = Routines::Generator.call(template: template, action_plan: plan, created_by: @user,
      period_start: Date.new(2026, 10, 5), period_end: Date.new(2026, 10, 7))
    @value = @routine.routine_values.first
  end

  test "currency save returns the same formatted value as the page and live update" do
    patch routine_value_path(@value), params: { routine_value: { value: "15888,20" } }, as: :json
    assert_response :success
    assert_equal "15888.20", @value.reload.value
    formatted = response.parsed_body.fetch("formatted_value")
    assert_equal "R$ 15.888,20", formatted

    get routine_path(@routine)
    assert_response :success
    assert_select "#routine-value-display-#{@value.id}.routine-cell__display", text: formatted

    stream = ApplicationController.render(partial: "routine_values/collaboration_update",
      formats: [:turbo_stream], locals: { routine_value: @value })
    display = Nokogiri::HTML.fragment(stream).at_css("#routine-value-display-#{@value.id}")
    assert_includes display["class"].split, "routine-cell__display"
    assert_equal "display", display["data-routine-cell-target"]
    assert_equal formatted, display.text
    assert Nokogiri::HTML.fragment(stream).at_css("#routine-result-#{@indicator.id}.result-value")
  end

  test "live updates escape text values while retaining the display styling" do
    @indicator.update!(value_type: :text, calculation_type: :last_value)
    @value.update!(value: '<img src=x onerror="alert(1)">')
    stream = ApplicationController.render(partial: "routine_values/collaboration_update",
      formats: [:turbo_stream], locals: { routine_value: @value })
    display = Nokogiri::HTML.fragment(stream).at_css(".routine-cell__display")
    assert_equal @value.value, display.text
    assert_empty display.css("img")
  end
end
