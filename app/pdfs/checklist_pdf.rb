require "prawn"
require "prawn/table"
require "open-uri"

class ChecklistPdf < Prawn::Document
  include Rails.application.routes.url_helpers

  def initialize(checklist)
    super(top_margin: 30)

    @checklist = checklist

    header
    checklist_details
    truck_photos_section

    if @checklist.checklist_template.photo_only?
      photo_only_section
    else
      checklist_items
    end

    signature_section
  end

  private

  # =========================
  # CABEÇALHO
  # =========================
  def header
    text "Checklist - #{@checklist.checklist_template.name}",
         size: 18,
         style: :bold

    move_down 10

    if @checklist.plate.present?
      text "Placa selecionada: #{@checklist.plate.placa}",
           size: 12

    elsif @checklist.placa_manual.present?
      text "Placa informada: #{@checklist.placa_manual}",
           size: 12
    end

    text "Data: #{I18n.l(@checklist.created_at, format: :short)}",
         size: 12

    move_down 15
  end

  # =========================
  # DETALHES DO CHECKLIST
  # =========================
  def checklist_details
    lines = []

    if @checklist.vehicle_model.present?
      lines << ["Modelo do veículo", @checklist.vehicle_model]
    end

    if @checklist.kilometer.present?
      lines << ["Quilometragem", "#{@checklist.kilometer} km"]
    end

    if @checklist.gas_state.present?

      gas_label = {
        "full" => "Cheio",
        "three_quarters" => "3/4",
        "half" => "1/2",
        "quarter" => "1/4",
        "empty" => "Vazio"
      }[@checklist.gas_state] || @checklist.gas_state

      lines << ["Nível de combustível", gas_label]
    end

    if @checklist.responsavel.present?
      lines << ["Responsável", @checklist.responsavel]
    end

    if @checklist.origin.present?
      lines << ["Origem", @checklist.origin]
    end

    return if lines.empty?

    table(
      lines,
      cell_style: {
        borders: [],
        padding: [3, 5]
      },
      column_widths: [200, 250]
    ) do

      cells.size = 12
      column(0).font_style = :bold
    end

    move_down 10
  end

  # =========================
  # FOTOS 360 DO CAMINHÃO
  # =========================
  def truck_photos_section
    photos = {
      "Frente" => @checklist.photo_front,
      "Lado esquerdo (cavalo)" => @checklist.photo_left_truck,
      "Lado esquerdo (implemento)" => @checklist.photo_left_trailer,
      "Traseira" => @checklist.photo_back,
      "Lado direito (implemento)" => @checklist.photo_right_trailer,
      "Lado direito (cavalo)" => @checklist.photo_right_truck
    }

    attached_photos =
      photos.select do |_label, photo|
        photo.attached?
      end

    return if attached_photos.empty?

    table(
      [[{
        content: "Fotos do Caminhão",
        align: :center,
        size: 14,
        font_style: :bold
      }]],
      width: bounds.width,
      cell_style: {
        borders: [:top, :bottom, :left, :right],
        border_width: 1,
        border_color: "000000",
        padding: [6, 0, 6, 0]
      }
    )

    attached_photos.each_slice(3) do |row_photos|

      row_data =
        row_photos.map do |label, photo|
          process_truck_photo(label, photo)
        end

      while row_data.length < 3
        row_data << [{ content: "" }, { content: "" }]
      end

      image_cells = row_data.map { |d| d[0] }
      label_cells = row_data.map { |d| d[1] }

      table(
        [image_cells, label_cells],
        width: bounds.width,
        cell_style: {
          borders: [:top, :left, :right, :bottom],
          align: :center
        }
      ) do |t|

        t.row(0).height = 120
        t.row(1).height = 15

        t.columns(0..2).width = bounds.width / 3

        t.row(0).valign = :center
      end
    end

    move_down 20
  end

  def process_truck_photo(label, photo)
    return unsupported_photo_cell(label) unless photo.image?

    begin
      url = photo.url(
        transformation: [
          {
            width: 1000,
            height: 1000,
            crop: "limit",
            quality: "auto:eco",
            fetch_format: "auto"
          }
        ]
      )

      file = URI.open(url)

      image_cell = {
        image: file,
        fit: [200, 100],
        position: :center,
        vposition: :center
      }

      label_cell = {
        content: label,
        align: :center,
        size: 10
      }

      [image_cell, label_cell]

    rescue
      error_photo_cell(label)
    end
  end

  def unsupported_photo_cell(label)
    [
      {
        content: "Formato não\nsuportado",
        align: :center,
        valign: :center,
        size: 8
      },
      {
        content: label,
        align: :center,
        size: 10
      }
    ]
  end

  def error_photo_cell(label)
    [
      {
        content: "Erro ao\ncarregar foto",
        align: :center,
        valign: :center,
        size: 8
      },
      {
        content: label,
        align: :center,
        size: 10
      }
    ]
  end

  # =========================
  # CHECKLIST PADRÃO
  # =========================
  def checklist_items
    return if @checklist.checklist_responses.empty?

    data = [["Descrição", "Status", "Comentário", "Foto"]]

    @checklist.checklist_responses.each do |resp|

      text_cell =
        resp.checklist_item&.description || "Sem descrição"

      status_cell =
        resp.status&.upcase || "N/A"

      comment_cell =
        resp.comment.presence || "-"

      photo_cell =
        if resp.photo.attached?

          if resp.photo.image?

            begin
              file = URI.open(resp.photo.url)

              {
                image: file,
                fit: [80, 80],
                position: :center
              }

            rescue
              "Erro ao carregar imagem"
            end

          else
            "Formato não suportado"
          end

        else
          ""
        end

      data << [
        text_cell,
        status_cell,
        comment_cell,
        photo_cell
      ]
    end

    table(
      data,
      header: true,
      column_widths: [200, 60, 150, 130]
    ) do

      row(0).font_style = :bold
      row(0).background_color = "DDDDDD"

      cells.padding = 5
      cells.valign = :center

      row(0).borders = [:top, :left, :right, :bottom]
    end

    move_down 40
  end

  # =========================
  # CHECKLIST FOTO ONLY
  # =========================
  def photo_only_section
    has_photos =
      @checklist.checklist_photos.any?

    has_defects =
      @checklist.checklist_defects.any?

    return unless has_photos || has_defects

    move_down 10

    text "Fotos de Evidências / Defeitos",
        size: 14,
        style: :bold

    move_down 10

    # =========================
    # FOTOS
    # =========================
    if has_photos

      photos_data = []

      @checklist.checklist_photos.each do |photo_record|

        kind_label =
          case photo_record.kind
          when "standard"
            "Foto padrão"
          when "defect"
            "Defeito"
          else
            photo_record.kind.to_s.humanize
          end

        image_content =
          if photo_record.photo.attached? && photo_record.photo.image?

            begin
              url = photo_record.photo.url(
                transformation: [
                  {
                    width: 1000,
                    height: 1000,
                    crop: "limit",
                    quality: "auto:eco",
                    fetch_format: "auto"
                  }
                ]
              )

              file = URI.open(url)

              {
                image: file,
                fit: [240, 180],
                position: :center
              }

            rescue
              {
                content: "Erro ao carregar imagem",
                align: :center,
                valign: :center
              }
            end

          else
            {
              content: "Imagem indisponível",
              align: :center,
              valign: :center
            }
          end

        description =
          if photo_record.description.present?
            "#{kind_label}\n#{photo_record.description}"
          else
            kind_label
          end

        photos_data << [
          image_content,
          {
            content: description,
            align: :center,
            size: 9,
            padding: [5, 5, 5, 5]
          }
        ]
      end

      photos_data.each_slice(2) do |slice|

        while slice.size < 2
          slice << [
            { content: "" },
            { content: "" }
          ]
        end

        image_row = slice.map { |item| item[0] }
        text_row  = slice.map { |item| item[1] }

        table(
          [image_row, text_row],
          width: bounds.width,
          column_widths: [bounds.width / 2, bounds.width / 2],
          cell_style: {
            borders: [:top, :bottom, :left, :right],
            border_width: 0.5,
            padding: 5,
            align: :center,
            valign: :center
          }
        ) do |t|
          t.row(0).height = 190
        end

        move_down 10
      end
    end

    # =========================
    # DEFEITOS SEM FOTO
    # =========================
    if has_defects

      move_down 15

      text "Defeitos sem Foto",
          size: 12,
          style: :bold

      move_down 8

      defects_data = [
        ["Local", "Descrição"]
      ]

      @checklist.checklist_defects.each do |defect|

        defects_data << [
          defect.location.presence || "-",
          defect.description.presence || "-"
        ]
      end

      table(
        defects_data,
        header: true,
        column_widths: [150, 350]
      ) do

        row(0).font_style = :bold
        row(0).background_color = "DDDDDD"

        cells.padding = 6
        cells.size = 10
        cells.valign = :center
      end
    end
  end

  # =========================
  # ASSINATURA
  # =========================
  def signature_section
    move_down 60

    table(
      [[
        {
          content: "______________________________\nResponsável pela assinatura",
          align: :center
        },
        {
          content: "______________________________\nData",
          align: :center
        }
      ]],
      cell_style: {
        borders: [],
        padding: [10, 10],
        size: 10
      },
      column_widths: [250, 250],
      position: :center
    )
  end
end