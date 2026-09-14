class ErrorsController < ActionController::Base
  REPORT_TTL = 1.hour

  def internal_server_error
    report_id = SecureRandom.hex(24)
    exception = request.env["action_dispatch.exception"]
    Rails.cache.write("error_report:#{report_id}", build_report(exception), expires_in: REPORT_TTL)

    render "errors/internal_server_error",
      status: :internal_server_error,
      locals: { report_id: report_id }
  end

  def download
    report = Rails.cache.read("error_report:#{params[:id]}")
    return head :not_found if report.blank?

    send_data report,
      filename: "erro_#{params[:id]}.log",
      type: "text/plain",
      disposition: "attachment"
  end

  private

  def build_report(exception)
    details = [
      "Workstation - relatório de erro",
      "Data: #{Time.current.iso8601}",
      "Request ID: #{request.request_id}",
      "Método: #{request.request_method}",
      "Caminho: #{request.fullpath}",
      ""
    ]

    if exception
      details << "Exceção: #{exception.class}"
      details << "Mensagem: #{exception.message}"
      details << ""
      details << "Backtrace:"
      details.concat(Array(exception.backtrace).first(100).map { |line| "  #{line}" })
    else
      details << "A aplicação retornou um erro 500 sem disponibilizar os detalhes da exceção."
    end

    details.join("\n")
  end
end
