module AiAssistant
  class PageContext
    class Unavailable < StandardError; end
    attr_reader :reference

    def initialize(user:, reference:)
      @user = user
      @reference = {}
      return if reference.blank?
      raise Unavailable unless user&.active? && reference.is_a?(Hash)

      args = reference.stringify_keys
      type = args["type"]
      raise Unavailable unless args["id"].is_a?(String) || args["id"].is_a?(Integer)
      id = Integer(args["id"])
      raise Unavailable unless id.positive?
      @record = case type
                when "plan" then ActionPlan.visible_to(user).find_by(id: id)
                when "task" then Task.accessible_to(user).includes(bucket: :action_plan).find_by(id: id)
                when "plate" then Plate.find_by(id: id) if Access.new(user).allowed?(:plates)
                end
      raise Unavailable unless @record
      @reference = { "type" => type, "id" => @record.id }
    rescue ArgumentError, TypeError
      raise Unavailable
    end

    def model_data
      return {} unless @record

      reference.merge("label" => label, "note" => "Referência da tela aberta; consulte as funções autorizadas antes de afirmar dados ou preparar alterações.")
    end

    def client_data
      return {} unless @record

      { reference: reference, label: label, shortcuts: shortcuts }
    end

    private

    def label
      name = case reference["type"]
             when "plan" then "Plano: #{@record.name}"
             when "task" then "Tarefa: #{@record.title}"
             when "plate" then "Veículo: #{@record.placa}"
             end
      name.to_s.truncate(180)
    end

    def shortcuts
      case reference["type"]
      when "plan"
        items = [shortcut("Resumir plano", "Resuma este plano de ação."), shortcut("Ver pendências", "Quais são as pendências deste plano?")]
        items << shortcut("Criar tarefa", "Quero criar uma tarefa neste plano.") if ActionDraft.allowed?(@user)
        items
      when "task"
        [shortcut("Resumir tarefa", "Resuma esta tarefa e seu prazo."), shortcut("Alterar prazo", "Quero alterar o prazo desta tarefa."),
         @record.completed? ? shortcut("Reabrir tarefa", "Prepare a reabertura desta tarefa.") : shortcut("Concluir tarefa", "Prepare a conclusão desta tarefa.")]
      when "plate"
        access = Access.new(@user)
        items = [shortcut("Ver pendências", "Quais tarefas pendentes mencionam este veículo?")]
        items << shortcut("Ver disponibilidade", "Como está a disponibilidade deste veículo hoje?") if access.allowed?(:availability)
        items << shortcut("Ver pneus", "Como estão os pneus deste veículo?") if access.allowed?(:tires)
        items
      end
    end

    def shortcut(label, question)
      { label: label, question: question }
    end
  end
end
