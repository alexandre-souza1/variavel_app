class ChecklistsController < ApplicationController
  before_action :authenticate_user!, except: [:new, :create, :show]
  before_action :set_template, only: [:new]

  def index
    @checklists = current_user.checklists.includes(:checklist_template)
  end

  def historic
    @checklists = Checklist.includes(:checklist_template)
  end

  def new
    @template = ChecklistTemplate.find(params[:template_id])

    @checklist =
      if user_signed_in?

        checklist = current_user.checklists.new(
          checklist_template: @template,
          status: "draft"
        )

        checklist.save(validate: false)

        checklist

      else

        checklist = Checklist.new(
          checklist_template: @template,
          status: "draft"
        )

        checklist.user =
          User.find_by(email: "anon@system.local")

        checklist.save(validate: false)

        checklist

      end

    if @template.photo_only?

      @checklist.checklist_photos.build

    else

      @template.checklist_items.each do |item|

        @checklist.checklist_responses.build(
          checklist_item: item
        )

      end

    end

    @plates = Plate.where(setor: @template.setor)
  end

  def create
    @template = ChecklistTemplate.find(checklist_params[:checklist_template_id])

    if user_signed_in?
      @checklist = current_user.checklists.new(checklist_params)
    else
      # cria o checklist sem usuário logado
      @checklist = Checklist.new(checklist_params)
      # define user_id como "usuário não registrado"
      # (criaremos um usuário padrão pra isso no passo 3)
      @checklist.user = User.find_by(email: "anon@system.local")
    end

    if @checklist.save
      redirect_to @checklist, notice: 'Checklist enviado com sucesso.'
    else
      @plates = Plate.where(setor: @template.setor)
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @checklist = Checklist.find(params[:id])

    if @checklist.update(checklist_params)

      @checklist.update(status: "completed")

      redirect_to @checklist,
                  notice: "Checklist enviado com sucesso."

    else

      @template = @checklist.checklist_template
      @plates = Plate.where(setor: @template.setor)

      render :new,
            status: :unprocessable_entity

    end
  end

  def show
      @checklist = Checklist.find(params[:id])
        respond_to do |format|
      format.html
      format.pdf do
        pdf = ChecklistPdf.new(@checklist)
        send_data pdf.render,
                  filename: "checklist_#{@checklist.id}.pdf",
                  type: "application/pdf",
                  disposition: "inline"
      end
    end
  end

  require "zip"

  def download_photos
    @checklist = Checklist.find(params[:id])

    compressed_filestream = Zip::OutputStream.write_buffer do |zos|

      @checklist.checklist_photos.each_with_index do |photo, index|

        next unless photo.photo.attached?

        filename =
          photo.photo.filename.to_s.presence ||
          "foto_#{index + 1}.jpg"

        zos.put_next_entry(filename)

        zos.write(photo.photo.download)
      end
    end

    compressed_filestream.rewind

    send_data compressed_filestream.read,
              filename: "checklist_#{@checklist.id}_fotos.zip",
              type: "application/zip"
  end

  def export_excel
    @checklist = Checklist.find(params[:id])

    respond_to do |format|
      format.xlsx do
        response.headers[
          'Content-Disposition'
        ] = "attachment; filename=checklist_#{@checklist.id}.xlsx"
      end
    end
  end

  private

  def autosave
    if params[:id].present?
      @checklist = Checklist.find(params[:id])
      @checklist.update(checklist_params)

    else
      @checklist = Checklist.new(checklist_params)

      if user_signed_in?
        @checklist.user = current_user
      else
        @checklist.user =
          User.find_by(email: "anon@system.local")
      end

      @checklist.status = "draft"

      @checklist.save(validate: false)
    end

    render json: {
      success: true,
      checklist_id: @checklist.id
    }
  end

  def set_template
    @template = ChecklistTemplate.find(params[:template_id])
  end

  def checklist_params
    params.require(:checklist).permit(
      :checklist_template_id,
      :plate_id,
      :placa_manual,
      :responsavel,
      :vehicle_model,
      :origin,
      :gas_state,
      :kilometer,
      :photo_front,
      :photo_left_truck,
      :photo_left_trailer,
      :photo_back,
      :photo_right_trailer,
      :photo_right_truck,
      checklist_photos_attributes: [
        :id,
        :photo,
        :kind,
        :description,
        :_destroy
      ],
      checklist_responses_attributes: [:id, :checklist_item_id, :status, :comment, :photo],
      checklist_defects_attributes: [
        :id,
        :description,
        :location,
        :_destroy
      ]
    )
  end
end
