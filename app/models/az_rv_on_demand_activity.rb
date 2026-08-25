class AzRvOnDemandActivity < ApplicationRecord
  belongs_to :az_rv_import

  scope :between, ->(start_date, end_date) { where(created_at_source: start_date.beginning_of_day..end_date.end_of_day) }

  RV_RATES = {
    amarracao: BigDecimal("1.25"),
    amarracao_carreta: BigDecimal("2.00"),
    desamarracao: BigDecimal("1.25"),
    qualidade: BigDecimal("0.50"),
    repack: BigDecimal("0.20"),
    ressuprimento: BigDecimal("1.50"),
    separacao_chopp: BigDecimal("1.00"),
    organizacao_devolucao: BigDecimal("1.00"),
    pre_picking: BigDecimal("1.00"),
    blitz_carregamento: BigDecimal("0.50"),
    blitz_retorno_rota: BigDecimal("1.10"),
    demais_atividades: BigDecimal("1.00"),
    ondemand_operacional: BigDecimal("0.10"),
    maquina_limpeza: BigDecimal("5.00"),
    remonte: BigDecimal("0.50")
  }.freeze

  def rv_category
    activity_key = normalize(activity)
    transport_key = normalize(transport_type)

    return :amarracao_carreta if transport_key == "spot" && amarracao_activity?(activity_key)
    return :amarracao if transport_key == "as" && amarracao_activity?(activity_key)
    return :qualidade if ["retrabalho/ptl", "pnc/ retrabalho", "pnc/retrabalho"].include?(activity_key)
    return :repack if activity_key.start_with?("repack -")
    return :ressuprimento if activity_key == "ressuprimento do picking"
    return :separacao_chopp if ["separacao chop", "separar chopp"].include?(activity_key)
    return :organizacao_devolucao if ["organizacao da devolucao", "reintegracao da devolucao"].include?(activity_key)
    return :pre_picking if activity_key == "markplace/bees - separacao pre picking"
    return :blitz_carregamento if activity_key == "blitz carregamento"
    return :blitz_retorno_rota if activity_key == "blitz retorno de rota"
    return :maquina_limpeza if activity_key == "maquina de limpeza"
    return :remonte if activity_key == "remonte de palete - pbr1/pbr2"
    return :ondemand_operacional if [
      "ajuste de empilhamento lote",
      "descarga",
      "rebaixamento de palete",
      "markplace/bees - recebimento/carregamento"
    ].include?(activity_key)
    return :demais_atividades if demais_activity?(activity_key)

    nil
  end

  def rv_quantity
    return BigDecimal("1") unless quantity_from_observation?

    value = observation.to_s.gsub(/\s+/, "")
    return BigDecimal("0") if value.blank?

    BigDecimal(value.delete(".").tr(",", "."))
  rescue ArgumentError
    BigDecimal("0")
  end

  def rv_amount
    category = rv_category
    return BigDecimal("0") unless category

    RV_RATES.fetch(category) * rv_quantity
  end

  private

  def amarracao_activity?(activity_key)
    ["amarracao", "desamarrar descarga"].include?(activity_key)
  end

  def quantity_from_observation?
    [
      :amarracao,
      :amarracao_carreta,
      :qualidade,
      :repack,
      :ressuprimento,
      :blitz_carregamento,
      :blitz_retorno_rota,
      :ondemand_operacional,
      :remonte
    ].include?(rv_category)
  end

  def demais_activity?(activity_key)
    [
      "ajuste de empilhamento lote",
      "separacao chapatex",
      "separacao itens marketing place",
      "separacao pallete/chapatex",
      "identificar pallets - nri",
      "carregamento van",
      "carregamento de veiculos",
      "colocar fitilho",
      "reabastecimento pre-picking",
      "limpeza repack",
      "5s-",
      "estreche",
      "descarga de empurrada",
      "descarga",
      "limpeza armazem",
      "recolha de quebra",
      "separacao palete",
      "pnc - filme strech",
      "rebaixamento de palete"
    ].include?(activity_key)
  end

  def normalize(value)
    value.to_s.strip.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
          .downcase.gsub(/\s+/, " ")
  end
end
