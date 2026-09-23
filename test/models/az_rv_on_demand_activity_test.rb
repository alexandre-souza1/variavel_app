require "test_helper"

class AzRvOnDemandActivityTest < ActiveSupport::TestCase
  test "Blitz quantity is halved before applying its rate including fractional quantities" do
    { "8" => "4", "10" => "5", "3" => "1.5" }.each do |observation, expected|
      activity = AzRvOnDemandActivity.new(activity: "Blitz carregamento", observation: observation)
      assert_equal BigDecimal(expected), activity.rv_quantity
      assert_equal BigDecimal(expected) * BigDecimal("0.50"), activity.rv_amount
    end
  end

  test "other activities follow the spreadsheet allowlist and count one per record" do
    ["Carregamento Van", "Identificar pallets - NRI", "MarkPlace/Bees - Recebimento/Carregamento",
     "Separação Chapatex", "Separação Itens Marketing Place", "Separação pallete/chapatex",
     "Carregamento de Veiculos", "Colocar Fitilho", "Reabastecimento Pré-picking"].each do |name|
      activity = AzRvOnDemandActivity.new(activity: name, observation: "10")
      assert_equal :demais_atividades, activity.rv_category, name
      assert_equal 1, activity.rv_quantity, name
      assert_equal 1, activity.rv_amount, name
    end
  end

  test "unlisted activities do not add units or remuneration" do
    ["5S-", "Estreche", "Limpeza Repack", "Recolha de quebra", "Descarga de Empurrada",
     "Limpeza Armazém", "PNC - Filme Strech", "DESCARTE DE AVARIAS - REPACK",
     "REINTEGRAÇÃO DE PRODUTOS - REPACK"].each do |name|
      activity = AzRvOnDemandActivity.new(activity: name, observation: "10")
      assert_nil activity.rv_category, name
      assert_equal 0, activity.rv_quantity, name
      assert_equal 0, activity.rv_amount, name
    end
  end

  test "remonte is shown separately but excluded from the grand total" do
    activity = AzRvOnDemandActivity.new(activity: "Remonte de Palete - PBR1/PBR2", observation: "25")

    assert_equal BigDecimal("12.50"), activity.rv_amount
    assert_equal BigDecimal("0"), activity.rv_total_amount
  end
end
