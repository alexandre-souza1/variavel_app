import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tipo", "campo", "unidade", "grupo", "sufixo"]

  connect() {
    this.atualizar()
  }

  atualizar() {
    const tipo = this.tipoTarget.value

    // Oculta se não houver seleção
    if (!tipo) {
      this.grupoTarget.style.display = "none"
      this.unidadeTarget.textContent = ""
      this.sufixoTarget.textContent = ""
      this.campoTarget.value = ""
      return
    }

    this.grupoTarget.style.display = "block"

    if (tipo === "tempo_atendimento") {
      this.campoTarget.step = 0.01
      this.campoTarget.placeholder = "Ex: 1.5"
      this.unidadeTarget.textContent = "Informe o tempo em horas (ex: 1.5 para 1h30)"
      this.sufixoTarget.textContent = "h"
    } else if (tipo === "eficiencia_carregamento" || tipo === "eficiencia_descarga") {
      this.campoTarget.step = 0.01
      this.campoTarget.placeholder = "Ex: 87.5"
      this.unidadeTarget.textContent = "Informe a porcentagem (ex: 87.5)"
      this.sufixoTarget.textContent = "%"
    } else {
      this.unidadeTarget.textContent = ""
      this.sufixoTarget.textContent = ""
    }
  }
}
