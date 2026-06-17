class ChecklistsController < ApplicationController
  ANONYMOUS_USER_EMAIL = "anon@system.local"

  before_action :authenticate_user!,
                except: [:new, :create, :show, :edit, :update, :autosave, :restart]
  before_action :set_template, only: [:new]

  def index
    @checklists = current_user.checklists.includes(:checklist_template)
  end

  def historic
    @checklists =
      if current_user.admin? || current_user.supervisor?
        Checklist.includes(:checklist_template)
      else
        current_user.checklists.includes(:checklist_template)
      end
  end

  def new
    @template =
      ChecklistTemplate.find(params[:template_id])

    # =========================
    # DEFINE O USUÁRIO
    # =========================

    user =
      checklist_user

    # =========================
    # PROCURA DRAFT EXISTENTE
    # =========================

    existing_draft =
      if user_signed_in?
        user.checklists.find_by(
          checklist_template: @template,
          status: "draft"
        )
      else
        draft_id =
          anonymous_checklist_ids[@template.id.to_s]

        user.checklists.find_by(
          id: draft_id,
          checklist_template: @template,
          status: "draft"
        )
      end

    # =========================
    # EXPIRA DRAFTS ANTIGOS
    # =========================

    if existing_draft.present? &&
      existing_draft.updated_at < 2.hours.ago

      existing_draft.destroy
      existing_draft = nil
    end

    # =========================
    # USA DRAFT OU CRIA NOVO
    # =========================

    @checklist =
      if existing_draft.present?

        existing_draft

      else

        checklist =
          user.checklists.new(
            checklist_template: @template,
            status: "draft"
          )

        checklist.save(validate: false)
        remember_anonymous_checklist(checklist)

        checklist
      end

    # =========================
    # MONTA CAMPOS INICIAIS
    # =========================

    prepare_checklist_form

    # =========================
    # PLACAS
    # =========================

    @plates =
      Plate.where(setor: @template.setor)
  end

  def edit
    @checklist = accessible_checklist
    @template = @checklist.checklist_template

    prepare_checklist_form

    @plates =
      Plate.where(setor: @template.setor)

    render :new
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
      @checklist.user = checklist_user
    end

    if @checklist.save
      remember_anonymous_checklist(@checklist)

      redirect_to @checklist, notice: 'Checklist enviado com sucesso.'
    else
      @plates = Plate.where(setor: @template.setor)
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @checklist = accessible_checklist

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

  def restart
    checklist = accessible_checklist

    checklist.destroy

    forget_anonymous_checklist(checklist)

    redirect_to new_checklist_path(
      template_id: checklist.checklist_template_id
    )
  end

  def show
    @checklist = accessible_checklist

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
    @checklist = accessible_checklist

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
    @checklist = accessible_checklist

    respond_to do |format|
      format.xlsx do
        response.headers[
          'Content-Disposition'
        ] = "attachment; filename=checklist_#{@checklist.id}.xlsx"
      end
    end
  end

  def autosave
    if params[:id].present?
      @checklist = accessible_checklist
      @checklist.update(checklist_params)

    else
      @checklist = Checklist.new(checklist_params)

      if user_signed_in?
        @checklist.user = current_user
      else
        @checklist.user = checklist_user
      end

      @checklist.status = "draft"

      @checklist.save(validate: false)
      remember_anonymous_checklist(@checklist)
    end

    render json: {
      success: true,
      checklist_id: @checklist.id
    }
  end

  private

  def checklist_user
    if user_signed_in?
      current_user
    else
      User.find_by!(email: ANONYMOUS_USER_EMAIL)
    end
  end

  def accessible_checklist
    if user_signed_in? && (current_user.admin? || current_user.supervisor?)
      return Checklist.find(params[:id])
    end

    checklist = checklist_user.checklists.find(params[:id])

    return checklist if user_signed_in?

    draft_id =
      anonymous_checklist_ids[checklist.checklist_template_id.to_s]

    raise ActiveRecord::RecordNotFound unless draft_id.to_i == checklist.id

    checklist
  end

  def anonymous_checklist_ids
    session[:anonymous_checklist_ids] ||= {}
  end

  def remember_anonymous_checklist(checklist)
    return if user_signed_in?

    checklist_ids =
      anonymous_checklist_ids

    checklist_ids[checklist.checklist_template_id.to_s] =
      checklist.id

    session[:anonymous_checklist_ids] =
      checklist_ids
  end

  def forget_anonymous_checklist(checklist)
    return if user_signed_in?

    checklist_ids =
      anonymous_checklist_ids

    checklist_ids.delete(
      checklist.checklist_template_id.to_s
    )

    session[:anonymous_checklist_ids] =
      checklist_ids
  end

  def prepare_checklist_form
    if @template.photo_only?

      if @checklist.checklist_photos.empty?
        @checklist.checklist_photos.build
      end

    else

      if @checklist.checklist_responses.empty?

        @template.checklist_items.each do |item|

          @checklist.checklist_responses.build(
            checklist_item: item
          )

        end

      end

    end
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
