class MeetingMinutesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_action_plan
  before_action :set_meeting, only: [:show, :create_tasks, :retry_generation, :audio, :update_content, :update_collaborator, :update_participants, :import_participants]
  before_action :ensure_meeting_access!, only: [:show, :create_tasks, :retry_generation, :audio, :update_content, :update_collaborator, :update_participants, :import_participants]
  before_action :ensure_content_edit_access!, only: [:update_content]
  before_action :ensure_collaborator_management_access!, only: [:update_collaborator]

  def index
    @meetings = @action_plan.meeting_minutes.order(meeting_date: :desc, created_at: :desc)
  end

  def new
    @meeting = @action_plan.meeting_minutes.new(
      meeting_date: Date.current,
      title: "Reunião - #{@action_plan.name}"
    )
  end

  def create
    @meeting = @action_plan.meeting_minutes.new(meeting_params)
    @meeting.creator = current_user
    @meeting.status = :queued

    if @meeting.save
      MeetingMinuteGenerationJob.perform_later(@meeting.id)
      redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
        notice: "A gravação foi recebida. A ata será gerada em segundo plano."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @buckets = @action_plan.buckets.order(:position)
    @users = User.active.order(:name)

    respond_to do |format|
      format.html
      format.pdf do
        pdf = MeetingMinutePdf.new(@meeting)

        send_data pdf.render,
          filename: "ata_#{@meeting.id}_#{@meeting.title.parameterize}.pdf",
          type: "application/pdf",
          disposition: params[:download].present? ? "attachment" : "inline"
      end
    end
  end

  def update_content
    unless @meeting.completed?
      redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
        alert: "Só é possível editar uma ata concluída."
      return
    end

    summary = meeting_content_params.key?(:summary) ? meeting_content_params[:summary].to_s.strip : @meeting.summary.to_s
    decisions = meeting_content_params.key?(:decisions) ? normalize_content_items(meeting_content_params[:decisions]) : Array(@meeting.decisions)
    pending_items = meeting_content_params.key?(:pending_items) ? normalize_content_items(meeting_content_params[:pending_items]) : Array(@meeting.pending_items)
    previous = {
      "summary" => @meeting.summary.to_s,
      "decisions" => Array(@meeting.decisions),
      "pending_items" => Array(@meeting.pending_items)
    }
    current = { "summary" => summary, "decisions" => decisions, "pending_items" => pending_items }

    if previous == current
      redirect_to action_plan_meeting_minute_path(@action_plan, @meeting), notice: "Nenhuma alteração foi feita."
      return
    end

    MeetingMinute.transaction do
      @meeting.update!(summary: summary, decisions: decisions, pending_items: pending_items)
      @meeting.edits.create!(user: current_user, changes_snapshot: { "before" => previous, "after" => current })
    end

    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting), notice: "Decisões e pendências atualizadas."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting), alert: e.message
  end

  def update_collaborator
    collaborator_id = params.dig(:meeting_minute, :collaborator_id).presence
    collaborator = User.active.find_by(id: collaborator_id) if collaborator_id

    if collaborator_id && collaborator.nil?
      redirect_to action_plan_meeting_minute_path(@action_plan, @meeting), alert: "Colaborador inválido."
      return
    end

    @meeting.update!(collaborator: collaborator)
    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting), notice: "Colaborador da ata atualizado."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting), alert: e.message
  end

  def retry_generation
    unless @meeting.failed?
      redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
        alert: "Esta ata não está disponível para reprocessamento."
      return
    end

    @meeting.update!(status: :queued, error_message: nil)
    MeetingMinuteGenerationJob.perform_later(@meeting.id)
    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
      notice: "A gravação foi mantida. A ata será tentada novamente em segundo plano."
  end

  def audio
    unless @meeting.audio.attached?
      redirect_to action_plan_meeting_minute_path(@action_plan, @meeting), alert: "A gravação de áudio não está disponível."
      return
    end

    redirect_to rails_blob_path(@meeting.audio, disposition: "attachment")
  end

  def create_tasks
    if @meeting.tasks_created?
      redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
        alert: "As tarefas sugeridas desta ata já foram criadas."
      return
    end

    suggestion_ids = Array(params[:suggestion_ids]).map(&:to_i)
    suggestions = Array(@meeting.tasks_suggestions)
    meeting_label = @action_plan.labels.find_or_create_by!(name: "Ata de Reunião") do |label|
      label.color = "#6f42c1"
    end

    created_count = 0

    ActiveRecord::Base.transaction do
      suggestion_ids.each do |index|
        suggestion = suggestions[index]
        next unless suggestion.present?

        bucket = @action_plan.buckets.find(params.dig(:bucket_ids, index.to_s))
        task = bucket.tasks.create!(
          title: suggestion["title"].presence || "Tarefa da reunião",
          description: suggestion["description"],
          start_at: Time.current,
          due_at: parse_due_date(suggestion["due_date"]),
          creator: current_user,
          user_ids: valid_user_ids(params.dig(:assignee_ids, index.to_s))
        )
        task.labels << meeting_label unless task.labels.exists?(meeting_label.id)
        created_count += 1 if task.persisted?
      end

      @meeting.update!(tasks_created: true) if created_count.positive?
    end

    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
      notice: "#{created_count} tarefa(s) criada(s) a partir da ata."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
      alert: "Não foi possível criar as tarefas: #{e.message}"
  end

  def update_participants
    if @meeting.update(participants_params)
      redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
        notice: "Participantes atualizados com sucesso."
    else
      redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
        alert: @meeting.errors.full_messages.to_sentence
    end
  end

  def import_participants
    imported_names = participant_source_names(params[:source], params[:sector])
    @meeting.update!(participants: @meeting.participants + imported_names)

    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
      notice: imported_names.any? ? "#{imported_names.size} participante(s) importado(s)." : "Nenhum participante encontrado."
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting), alert: e.message
  end

  private

  def parse_due_date(value)
    Date.parse(value).end_of_day if value.present?
  rescue ArgumentError
    nil
  end

  def valid_user_ids(value)
    Array(value).reject(&:blank?).map(&:to_i).then { |ids| User.where(id: ids).pluck(:id) }
  end

  def set_action_plan
    @action_plan = accessible_action_plans.find(params[:action_plan_id])
  end

  def set_meeting
    @meeting = @action_plan.meeting_minutes.find(params[:id])
  end

  def ensure_meeting_access!
    return if current_user.admin? || @meeting.creator_id == current_user.id ||
      @meeting.collaborator_id == current_user.id || @action_plan.user_id == current_user.id

    redirect_to action_plans_path, alert: "Você não possui acesso a esta ata."
  end

  def accessible_action_plans
    ActionPlan.visible_to(current_user)
  end

  def meeting_params
    params.require(:meeting_minute).permit(:title, :meeting_date, :audio, :participants)
  end

  def participants_params
    params.require(:meeting_minute).permit(:participants)
  end

  def meeting_content_params
    params.require(:meeting_minute).permit(:summary, decisions: [], pending_items: [])
  end

  def normalize_content_items(value)
    Array(value).flat_map { |item| item.to_s.split(/\r?\n/) }.map(&:strip).reject(&:blank?)
  end

  def ensure_content_edit_access!
    return if current_user.admin? || @meeting.creator_id == current_user.id || @meeting.collaborator_id == current_user.id

    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting), alert: "Você não possui permissão para editar esta ata."
  end

  def ensure_collaborator_management_access!
    return if current_user.admin? || @meeting.creator_id == current_user.id

    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting), alert: "Somente o criador ou um administrador pode indicar o colaborador."
  end

  def participant_source_names(source, sector)
    case source
    when "users_by_sector"
      sector_value = User.sectors[sector.to_s]
      raise ArgumentError, "Selecione um setor válido." if sector_value.nil?

      User.active.where(sector: sector_value).where.not(name: [nil, ""]).order(:name).pluck(:name)
    when "drivers"
      Driver.active.where.not(nome: [nil, ""]).order(:nome).pluck(:nome)
    when "operators"
      Operator.active.where.not(nome: [nil, ""]).order(:nome).pluck(:nome)
    when "ajudantes"
      Ajudante.active.where.not(nome: [nil, ""]).order(:nome).pluck(:nome)
    when "az_ajudantes"
      AzAjudante.active.where.not(nome: [nil, ""]).order(:nome).pluck(:nome)
    else
      raise ArgumentError, "Selecione uma origem válida."
    end
  end
end
