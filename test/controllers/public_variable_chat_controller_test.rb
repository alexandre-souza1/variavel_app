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
end
