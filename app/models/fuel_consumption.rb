require 'csv'

class FuelConsumption < ApplicationRecord
  # Callback
  before_save :normalize_driver_name

  def self.import(file, period:)
    CSV.foreach(file.path, headers: true, col_sep: detect_separator(file)) do |row|
      next if row["Motorista"].blank?

      FuelConsumption.create!(
        driver_name: row["Motorista"],
        km_per_liter: row["Km/Litro"].to_s.tr(",", "."),
        km_per_liter_goal: row["Km/Litro meta"].to_s.tr(",", "."),
        impact: row["Impacto"].to_s.tr(",", "."),
        total_value: row["Valor total"].to_s.tr(",", "."),
        refuelings_count: row["Nº abastecimentos"],
        liters: row["Litros abastecidos"].to_s.tr(",", "."),
        km_driven: row["Km rodado"].to_s.tr(",", "."),
        co2_impact: row["Impacto CO²"].to_s.tr(",", "."),
        period: period
      )
    end
  end

  def self.detect_separator(file)
    sample = File.open(file.path, &:readline)
    if sample.include?("\t")
      "\t"
    elsif sample.include?(";")
      ";"
    else
      ","
    end
  end

  private

  def normalize_driver_name
    return if driver_name.blank?
    self.driver_name = driver_name.strip.gsub(/\s+/, " ")
  end
end
