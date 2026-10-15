require "test_helper"

class AiAssistantsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "requires login for history and messages" do
    sign_out users(:one)
    get ai_assistant_path, as: :json
    assert_response :unauthorized
    post ai_assistant_path, params: { question: "Minhas tarefas" }, as: :json
    assert_response :unauthorized
    delete ai_assistant_path, as: :json
    assert_response :unauthorized
    assert_equal 0, AiConversation.count
  end

  test "history and clearing are always scoped to the logged in account even with forged ids" do
    other = AiConversation.create!(user: users(:two))
    other.ai_messages.create!(role: "user", content: "Conversa privada do outro usuário")
    mine = AiConversation.create!(user: users(:one))
    mine.ai_messages.create!(role: "assistant", content: "Meu histórico")

    get ai_assistant_path, params: { user_id: users(:two).id, conversation_id: other.id }, as: :json
    assert_response :success
    assert_equal ["Meu histórico"], response.parsed_body["messages"].map { |m| m["content"] }
    assert_includes response.headers["Cache-Control"], "no-store"

    delete ai_assistant_path, params: { user_id: users(:two).id, conversation_id: other.id }, as: :json
    assert_response :success
    assert_empty mine.ai_messages.reload
    assert_equal 1, other.ai_messages.count
  end

  test "queues the question under the current user and prevents concurrent requests" do
    with_api_key do
      assert_enqueued_with(job: AiAssistantJob) do
        post ai_assistant_path, params: { question: "Minhas pendências", user_id: users(:two).id }, as: :json
      end
      assert_response :accepted
      assert response.parsed_body["processing"]
      conversation = users(:one).reload.ai_conversation
      assert_equal "Minhas pendências", conversation.ai_messages.last.content
      assert_nil users(:two).reload.ai_conversation

      assert_no_difference "AiMessage.count" do
        post ai_assistant_path, params: { question: "Outra pergunta" }, as: :json
      end
      assert_response :conflict
    end
  end

  test "rejects empty oversized and unconfigured requests without queueing" do
    with_api_key do
      [" ", "a" * 2001].each do |question|
        assert_no_enqueued_jobs do
          post ai_assistant_path, params: { question: question }, as: :json
        end
        assert_response :unprocessable_entity
      end
    end
    previous = ENV.delete("GEMINI_API_KEY")
    post ai_assistant_path, params: { question: "Olá" }, as: :json
    assert_response :service_unavailable
  ensure
    ENV["GEMINI_API_KEY"] = previous if previous
  end

  test "clearing does not reset the hourly usage limit" do
    with_api_key do
      conversation = AiConversation.create!(user: users(:one), usage_count: 20, usage_window_at: Time.current)
      delete ai_assistant_path, as: :json
      post ai_assistant_path, params: { question: "Minhas tarefas" }, as: :json
      assert_response :too_many_requests
      assert_equal 20, conversation.reload.usage_count
    end
  end

  test "stores only the authorized reference per question so tabs cannot replace a queued context" do
    first = action_plans(:one)
    second = action_plans(:two)
    with_api_key do
      post ai_assistant_path, params: { question: "Resuma este plano", page_context: { type: "plan", id: first.id, label: "Forjado", role: "admin" } }, as: :json
      assert_response :accepted
      conversation = users(:one).reload.ai_conversation
      first_message = conversation.ai_messages.last
      assert_equal({ "type" => "plan", "id" => first.id }, first_message.page_context)
      conversation.finish!(conversation.request_token, answer: { content: "Resumo", sources: [] })
      post ai_assistant_path, params: { question: "Quais pendências tenho aqui?", page_context: { type: "plan", id: second.id } }, as: :json
      assert_response :accepted
      assert_equal second.id, conversation.ai_messages.last.page_context["id"]
      assert_equal first.id, first_message.reload.page_context["id"]
    end
  end

  test "forged inaccessible page references cannot start jobs or expose another inbox" do
    users(:one).update!(role: :user, sector: :fleet, name: "Ana")
    users(:two).update!(name: "Bruno")
    plan = users(:two).action_plans.create!(name: "Restrito", sector: :warehouse, public: false)
    private_task = users(:two).personal_inbox!.tasks.create!(title: "Segredo", creator: users(:two))
    with_api_key do
      [{ type: "plan", id: plan.id }, { type: "task", id: private_task.id }].each do |reference|
        assert_no_difference "AiMessage.count" do
          assert_no_enqueued_jobs do
            post ai_assistant_path, params: { question: "Resuma isto", page_context: reference, user_id: users(:two).id }, as: :json
          end
          assert_response :unprocessable_entity
        end
      end
    end
    get action_plan_path(action_plans(:one))
    assert_response :success
    assert_select ".ai-assistant[data-ai-assistant-page-value]" do |elements|
      assert_equal action_plans(:one).id, JSON.parse(elements.first["data-ai-assistant-page-value"])["reference"]["id"]
    end
    get inbox_path
    assert_select ".ai-assistant[data-ai-assistant-page-value='{}']"
  end

  private

  def with_api_key
    previous = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-key"
    yield
  ensure
    ENV["GEMINI_API_KEY"] = previous
  end
end
