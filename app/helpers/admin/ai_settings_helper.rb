module Admin::AiSettingsHelper
  def ai_settings_tab_path(tab, **options)
    edit_admin_ai_setting_path(@usage_report.filters.merge(tab: tab).merge(options).compact)
  end

  def ai_usage_number(value)
    value.nil? ? "—" : number_with_delimiter(value, delimiter: ".")
  end

  def ai_usage_status(request)
    return ["Sem chamadas registradas", "muted"] unless request
    return ["Limite atingido na última chamada", "warning"] if request.http_status == 429
    return ["Última chamada concluída", "success"] if request.http_status&.between?(200, 299)

    ["Falha na última chamada", "danger"]
  end
end
