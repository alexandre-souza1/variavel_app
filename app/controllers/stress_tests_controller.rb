class StressTestsController < ApplicationController
  before_action :authenticate_user!

  def index
    @last_import = StressTestImport
      .includes(:user)
      .order(imported_at: :desc)
      .first
  end

  def import
    if params[:file].blank?
      redirect_to stress_tests_path, alert: "Selecione um arquivo CSV."
      return
    end

    StressTestImportService.new(
      file: params[:file],
      user: current_user
    ).call

    redirect_to stress_tests_path,
                notice: "Arquivo importado com sucesso."
  end

  def imports
    @imports = StressTestImport
                .includes(:user, :stress_test_events)
                .order(created_at: :desc)
  end

  def import_details
    @import = StressTestImport
                  .includes(stress_test_events: :plate, user: [])
                  .find(params[:id])

    @events = @import.stress_test_events
                    .order(operation_date: :desc, operation_time: :desc)
  end
end
