require "test_helper"
require "minitest/mock"

class PublicVariableChatControllerTest < ActionDispatch::IntegrationTest
  setup { sign_out users(:one) }

  test "permite abrir o chat sem login" do
    get public_variable_chat_url

    assert_response :success
    assert_select "h1", /Converse com sua variável/
  end

  test "cria uma sessão somente com perfil, matrícula e nascimento válidos" do
    post identify_public_variable_chat_url, params: {
      profile: "az_ajudante",
      registration: az_ajudantes(:one).matricula,
      birth_date: az_ajudantes(:one).data_nascimento
    }

    assert_redirected_to public_variable_chat_url
    follow_redirect!
    assert_select "strong", text: az_ajudantes(:one).nome
  end

  test "não identifica cadastro com nascimento incorreto" do
    post identify_public_variable_chat_url, params: {
      profile: "az_ajudante",
      registration: az_ajudantes(:one).matricula,
      birth_date: "1990-01-01"
    }

    assert_redirected_to public_variable_chat_url
    follow_redirect!
    assert_select ".alert", /Não encontramos esse cadastro/
  end

  test "retorna ao local de origem e reabre o widget ao iniciar e encerrar" do
    return_to = "/?force_home=true"

    post identify_public_variable_chat_url, params: {
      profile: "az_ajudante",
      registration: az_ajudantes(:one).matricula,
      birth_date: az_ajudantes(:one).data_nascimento,
      return_to: return_to
    }

    assert_redirected_to return_to
    assert_equal true, session[:public_variable_chat_open]

    delete logout_public_variable_chat_url, params: { return_to: return_to }

    assert_redirected_to return_to
    assert_equal true, session[:public_variable_chat_open]
  end

  test "responde em JSON para atualizar o chat sem recarregar a página" do
    post identify_public_variable_chat_url, params: {
      profile: "az_ajudante",
      registration: az_ajudantes(:one).matricula,
      birth_date: az_ajudantes(:one).data_nascimento
    }

    service = Minitest::Mock.new
    service.expect :call, "Você ganhou R$ 100,00 neste mês."

    PublicVariableChatService.stub(:new, ->(**_args) { service }) do
      post message_public_variable_chat_url,
        params: { question: "Quanto ganhei este mês?" },
        as: :json
    end

    assert_response :success
    assert_equal "Você ganhou R$ 100,00 neste mês.", response.parsed_body["answer"]
    service.verify
  end

  test "identified visitors appear by name in admin usage without private messages or identification data" do
    previous_key = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "public-usage-test"
    AiApiRequest.delete_all
    employee = Employee.create!(nome: "Carolina Colaboradora", matricula: "AI-VISITOR", data_nascimento: "1995-03-18")
    other = Employee.create!(nome: "Outra Pessoa", matricula: "AI-OTHER", data_nascimento: "1991-07-10")
    post identify_public_variable_chat_url, params: {
      registration: employee.matricula, birth_date: employee.data_nascimento
    }
    provider = Faraday::Response.new(status: 200, body: {
      outputs: [{ text: "RESPOSTA_PRIVADA_COLABORADOR" }], usage: { total_input_tokens: 80, total_output_tokens: 10 }
    }.to_json)
    Faraday.stub(:post, ->(*_args, &_block) { provider }) do
      assert_difference "AiApiRequest.count", 1 do
        post message_public_variable_chat_url, params: {
          question: "PERGUNTA_PRIVADA_COLABORADOR", collaborator_id: other.id,
          collaborator_type: "Employee", user_id: users(:two).id
        }, as: :json
      end
    end
    assert_response :success
    usage = AiApiRequest.last
    assert_equal employee, usage.collaborator
    assert_nil usage.user_id
    assert_equal 80, usage.input_tokens

    sign_in users(:one)
    queries = []
    ActiveSupport::Notifications.subscribed(->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }, "sql.active_record") do
      get edit_admin_ai_setting_url(tab: "users", user_query: "Carolina")
    end
    assert_response :success
    assert_select ".ai-report-users__table tbody tr", count: 1
    assert_select ".ai-report-users__table", text: /Carolina Colaboradora/
    assert_select ".ai-report-user-kind", text: "Colaborador"
    %w[PERGUNTA_PRIVADA_COLABORADOR RESPOSTA_PRIVADA_COLABORADOR AI-VISITOR 1995-03-18].each do |private_value|
      refute_includes response.body, private_value
      refute_includes usage.attributes.values, private_value
    end
    refute queries.any? { |query| query.match?(/\b(ai_messages|ai_conversations|data_nascimento|cpf|matricula)\b/) },
      "Usage reports must not query conversations or identification data"
  ensure
    ENV["GEMINI_API_KEY"] = previous_key
  end

  test "legacy visitor usage is identified and invalid birth dates do not generate calls" do
    previous_key = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "legacy-usage-test"
    person = az_ajudantes(:one)
    post identify_public_variable_chat_url, params: {
      profile: "az_ajudante", registration: person.matricula, birth_date: "1990-01-01"
    }
    assert_no_difference "AiApiRequest.count" do
      post message_public_variable_chat_url, params: { question: "Teste" }, as: :json
    end
    assert_response :unauthorized
    post identify_public_variable_chat_url, params: {
      profile: "az_ajudante", registration: person.matricula, birth_date: person.data_nascimento
    }
    provider = Faraday::Response.new(status: 200, body: { outputs: [{ text: "Resposta" }] }.to_json)
    Faraday.stub(:post, ->(*_args, &_block) { provider }) do
      post message_public_variable_chat_url, params: { question: "Teste" }, as: :json
    end
    assert_response :success
    assert_equal person, AiApiRequest.last.collaborator
    assert_nil AiApiRequest.last.user_id
  ensure
    ENV["GEMINI_API_KEY"] = previous_key
  end
end
