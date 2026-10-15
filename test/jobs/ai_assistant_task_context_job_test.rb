require "test_helper"
require "minitest/mock"

class AiAssistantTaskContextJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @conversation = AiConversation.create!(user: @user, request_token: "request-1", requested_at: Time.current)
    @task = tasks(:one)
  end

  test "provider receives current task reference and prepares an update without changing the task" do
    message = @conversation.ai_messages.create!(role: "user", content: "Conclua esta tarefa", page_context: { type: "task", id: @task.id })
    requests = run_responses(message, [
      { steps: [{ type: "function_call", id: "read-1", name: "task_details", arguments: { task_id: @task.id } }] },
      { steps: [{ type: "function_call", id: "draft-1", name: "prepare_task_update", arguments: { task_id: @task.id, changes: { completed: true } } }] },
      { steps: [{ type: "model_output", content: [{ type: "text", text: "Confira as alterações antes de confirmar." }] }] }
    ])
    refute @task.reload.completed?
    action = @conversation.ai_action_requests.sole
    assert_equal "update_task", action.kind
    assert_equal "pending", action.status
    assert_equal ["Situação"], action.preview["changes"].pluck("label")
    first_input = JSON.parse(requests.first["input"].first["content"].first["text"])
    assert_equal @task.id, first_input["page_context"]["id"]
    assert_equal "task", first_input["page_context"]["type"]
    assert requests.all? { |request| request["store"] == false }
    refute requests.any? { |request| request.to_json.include?(action.confirmation_token) }
  end

  test "a reference authorized when queued is rechecked before sending data to the provider" do
    @user.update!(role: :user, sector: :fleet)
    plan = users(:two).action_plans.create!(name: "Sigilo do Armazém", public: true, sector: :warehouse)
    message = @conversation.ai_messages.create!(role: "user", content: "Resuma este plano", page_context: { type: "plan", id: plan.id })
    plan.update!(public: false)
    requests = run_responses(message, [{ steps: [{ type: "model_output", content: [{ type: "text", text: "Abra um registro autorizado novamente." }] }] }])
    input = JSON.parse(requests.first["input"].first["content"].first["text"])
    assert_equal false, input["page_context"]["available"]
    refute_includes requests.first.to_json, "Sigilo do Armazém"
    assert_empty @conversation.ai_action_requests
  end

  private

  def run_responses(message, responses)
    requests = []
    post = lambda do |_url, &block|
      req = Struct.new(:headers, :options, :body).new({}, Struct.new(:timeout, :open_timeout).new)
      block.call(req)
      requests << JSON.parse(req.body)
      Faraday::Response.new(status: 200, body: responses.shift.to_json)
    end
    previous = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-key"
    Faraday.stub(:post, post) { AiAssistantJob.perform_now(@conversation.id, "request-1", message.id) }
    assert_nil @conversation.reload.error_message
    requests
  ensure
    ENV["GEMINI_API_KEY"] = previous
  end
end
