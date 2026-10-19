require "nokogiri"

class InvoiceNfeXmlService
  class Error < StandardError; end

  def initialize(content)
    @content = content
  end

  def call
    xml = Nokogiri::XML(@content) { |config| config.strict.nonet }
    xml.remove_namespaces!
    info = xml.at_xpath("//NFe/infNFe") || raise(Error, "XML não contém uma NF-e")
    number = value(info, "ide/nNF")
    raise Error, "nota sem número no XML" if number.blank?

    cnpj = value(info, "emit/CNPJ").gsub(/\D/, "")
    raise Error, "nota sem CNPJ do emitente no XML" unless cnpj.length == 14

    total = BigDecimal(value(info, "total/ICMSTot/vNF"), exception: false)
    raise Error, "valor total inválido no XML" unless total&.finite?

    date = value(info, "ide/dhEmi").presence || value(info, "ide/dEmi")
    {
      invoice_number: number,
      supplier_name: value(info, "emit/xNome"),
      supplier_cnpj: cnpj,
      total: total,
      date_issued: Date.iso8601(date.first(10)).iso8601,
      cost_center_id: cost_center_from(info)
    }
  rescue Nokogiri::XML::SyntaxError
    raise Error, "XML malformado"
  rescue Date::Error
    raise Error, "data de emissão inválida no XML"
  end

  private

  def value(node, path)
    node.at_xpath(path)&.text.to_s.strip
  end

  def cost_center_from(info)
    text = value(info, "infAdic/infCpl")
    plate = text[/PLACA\s*:?\s*([A-Z0-9-]{6,})/i, 1]&.upcase
    plate ||= value(info, "transp/veicTransp/placa").presence&.upcase
    if plate.present?
      return CostCenter.where("UPPER(name) LIKE ?", "%#{plate}%").pick(:id)
    end

    normalized = text.upcase.gsub(/[^A-Z0-9]/, "")
    CostCenter.find_each do |center|
      name = center.name.to_s.upcase.gsub(/[^A-Z0-9]/, "")
      return center.id if name.present? && normalized.include?(name)
    end
    nil
  end
end
