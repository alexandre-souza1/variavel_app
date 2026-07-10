require "csv"

class StressTestImportService
  def initialize(file:, user:)
    @file = file
    @user = user
  end

  def call
    import = StressTestImport.create!(
      user: @user,
      imported_at: Time.current
    )

    csv = CSV.new(
      File.open(@file.path, "r:bom|utf-8"),
      headers: true,
      col_sep: ";"
    )


    count = 0

    csv.each do |row|

      placa = row["Placa"]&.strip

      plate = Plate.find_by(placa: placa)

      StressTestEvent.create!(
        stress_test_import: import,
        plate: plate,
        placa: placa,
        mapa: row["Mapa"]&.strip,
        fase: row["Fase"]&.strip,
        motorista: row["Motorista"]&.strip,
        destino: row["Destino"]&.strip,
        operation_date: parse_date(row["DtOper"]),
        operation_time: parse_time(row["HrOper"])
      )

      count += 1
    end

    Rails.logger.info "Importados #{count} registros."

    import
  end

  private

  def parse_date(value)
    return nil if value.blank?

    Date.strptime(value.strip, "%d/%m/%Y")
  rescue
    nil
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.strip)
  rescue
    nil
  end
end
