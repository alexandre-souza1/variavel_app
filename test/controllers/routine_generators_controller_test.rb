require "test_helper"

class RoutineGeneratorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @template = create_template_with_indicators
  end

  test "should get new" do
    get new_routine_template_generator_path(@template)
    assert_response :success
    assert_select "input[type=checkbox][name='indicator_ids[]']"
  end

  test "should create routine with all indicators by default" do
    assert_difference("Routine.count", 1) do
      post routine_template_generator_path(@template), params: {
        period_start: "2026-07-01",
        period_end: "2026-07-31"
      }
    end

    routine = Routine.last
    assert_equal 36, routine.routine_values.count
  end

  test "should create routine with selected indicators only" do
    daily_indicator = @template.routine_categories.first.routine_indicators.first
    weekly_indicator = @template.routine_categories.first.routine_indicators.second

    assert_difference("Routine.count", 1) do
      post routine_template_generator_path(@template), params: {
        period_start: "2026-07-01",
        period_end: "2026-07-31",
        indicator_ids: [daily_indicator.id, weekly_indicator.id]
      }
    end

    routine = Routine.last
    assert_equal 35, routine.routine_values.count
  end

  test "should get edit" do
    routine = create_routine_with_all_indicators
    get "/routines/#{routine.id}/generator/edit"
    assert_response :success
    assert_select "input[type=checkbox][name='indicator_ids[]']"
  end

  test "should update routine indicators" do
    routine = create_routine_with_all_indicators
    assert_equal 36, routine.routine_values.count

    daily_indicator = @template.routine_categories.first.routine_indicators.first
    weekly_indicator = @template.routine_categories.first.routine_indicators.second

    patch "/routines/#{routine.id}/generator", params: {
      indicator_ids: [daily_indicator.id, weekly_indicator.id]
    }

    assert_redirected_to routine
    routine.reload
    assert_equal 35, routine.routine_values.count
  end

  private

  def create_template_with_indicators
    template = RoutineTemplate.create!(name: "Test template #{Time.current.to_i}")
    category = template.routine_categories.create!(name: "Main", position: 0)
    
    category.routine_indicators.create!(
      name: "Daily",
      position: 0,
      response_frequency: :daily
    )
    
    category.routine_indicators.create!(
      name: "Weekly",
      position: 1,
      response_frequency: :weekly
    )
    
    category.routine_indicators.create!(
      name: "Monthly",
      position: 2,
      response_frequency: :monthly
    )
    
    template
  end

  def create_routine_with_all_indicators
    Routine.create!(
      routine_template: @template,
      created_by: @user,
      title: "Test Routine #{Time.current.to_i}",
      period_start: Date.new(2026, 7, 1),
      period_end: Date.new(2026, 7, 31),
      status: :open
    ).tap { |routine| routine.ensure_expected_values! }
  end
end


