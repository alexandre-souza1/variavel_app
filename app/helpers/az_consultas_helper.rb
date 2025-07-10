module AzConsultasHelper
  def nome_legivel_parametro(chave)
    {
      "valor_efc" => "Eficiência de Carregamento",
      "valor_tma" => "Tempo Médio de Atendimento",
      "valor_efd" => "Eficiência de Descarga",
      "tarefa_wms" => "Tarefas WMS"
    }[chave] || chave.to_s.titleize
  end

  def sufixo_parametro(nome)
    sufixos = {
      "Eficiência de Carregamento" => "/dia",
      "Eficiência de Descarga" => "/dia",
      "Tempo médio de atendimento" => "/dia",
      "Tarefas WMS" => "/cada"
    }
    sufixos[nome] || ""
  end

  def formatar_tempo(minutos)
    return '00:00' if minutos.nil?

    minutos = minutos.to_f
    horas = (minutos / 60).floor
    minutos_restantes = (minutos % 60).round

    # Garante que sempre tenha dois dígitos
    "#{horas.to_s.rjust(2, '0')}:#{minutos_restantes.to_s.rjust(2, '0')}"
  end
end
