require "test_helper"
require "minitest/mock"

class MeetingMinuteGenerationJobTest < ActiveJob::TestCase
  setup do
    @meeting = MeetingMinute.new(action_plan: action_plans(:one), creator: users(:one),
      title: "Reunião de teste", meeting_date: Date.current, status: :queued)
    @meeting.save!(validate: false)
  end

  test "attributes processing to the user who requested it" do
    run_with_actor(users(:two)) { MeetingMinuteGenerationJob.perform_now(@meeting.id, users(:two).id) }
    assert @meeting.reload.completed?
  end

  test "jobs already queued without an actor remain compatible and use the creator" do
    run_with_actor(users(:one)) { MeetingMinuteGenerationJob.perform_now(@meeting.id) }
    assert @meeting.reload.completed?
  end

  private

  def run_with_actor(expected)
    service = Minitest::Mock.new
    service.expect(:call, { "summary" => "Ata concluída", "decisions" => [], "pending_items" => [], "tasks" => [] })
    factory = lambda do |meeting, user:|
      assert_equal @meeting.id, meeting.id
      assert_equal expected.id, user.id
      service
    end
    GeminiMeetingService.stub(:new, factory) { yield }
    service.verify
  end
end
