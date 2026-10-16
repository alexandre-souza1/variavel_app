module Automations
  module Message
    TOKENS = %w[valor periodo automacao].freeze

    def self.validate!(text, required: false, max: 2000)
      raise Invalid, "Preencha o texto da ação." if required && text.blank?
      raise Invalid, "O texto da ação excede #{max} caracteres." if text.to_s.length > max
      unknown = text.to_s.scan(/\{\{\s*(.*?)\s*\}\}/).flatten - TOKENS
      raise Invalid, "Use somente as variáveis {{valor}}, {{periodo}} e {{automacao}}." if unknown.any?
    end

    def self.render(text, rule:, period:, result:)
      value = rule.operation == "count" ? result[:value].to_i.to_s :
        ActiveSupport::NumberHelper.number_to_currency(result[:value], unit: "R$ ", separator: ",", delimiter: ".")
      dates = period.start_date ? "#{I18n.l(period.start_date)} a #{I18n.l(period.end_date)}" : "todo o histórico até #{I18n.l(period.end_date)}"
      values = { "valor" => value, "periodo" => dates, "automacao" => rule.name }
      text.to_s.gsub(/\{\{\s*(.*?)\s*\}\}/) { values.fetch(Regexp.last_match(1)) }
    end

    def self.summary(rule, period:, result:)
      render("Automação: {{automacao}}\nResultado: {{valor}}\nPeríodo: {{periodo}}", rule: rule, period: period, result: result)
    end
  end
end
