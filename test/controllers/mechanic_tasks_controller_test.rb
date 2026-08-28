require "test_helper"

class MechanicTasksControllerTest < ActionDispatch::IntegrationTest
  test "mecânico vê apenas a própria lista de tarefas" do
    user = users(:one)
    user.update!(role: :mechanical)
    sign_in user

    get mechanic_tasks_path

    assert_response :success
    assert_select "h1", "Minhas tarefas"
    assert_select ".mechanic-task", count: 1
  end

  test "usuário comum não acessa a página do mecânico" do
    user = users(:one)
    user.update!(role: :user)
    sign_in user

    get mechanic_tasks_path

    assert_redirected_to root_path
  end

  test "mecânico não é tratado como usuário de setor na home" do
    user = users(:one)
    user.update!(role: :mechanical, sector: :fleet)
    sign_in user

    assert_not user.sector_fleet?
    get root_path

    assert_redirected_to mechanic_tasks_path
  end
end
