import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tipo", "campoWrapper", "campoHora", "campoMinuto", "unidade", "grupo", "sufixo"]

  connect() {
    this.atualizar()
  }

  atualizar() {
    const tipo = this.tipoTarget.value

    if (!tipo) {
      this.grupoTarget.style.display = "none"
      this.sufixoTarget.style.display = "none"
      this.unidadeTarget.textContent = ""
      this.sufixoTarget.textContent = ""
      this.campoWrapperTarget.innerHTML = ""
      return
    }

    this.grupoTarget.style.display = "block"

    if (tipo === "tempo_atendimento") {
      this.unidadeTarget.textContent = "Selecione horas e minutos"
      this.sufixoTarget.textContent = "h"
      this.montarSelectHorasMinutos()
    } else {
      // Número normal (porcentagem ou outro)
      this.unidadeTarget.textContent = tipo.includes("eficiencia") ? "Informe a porcentagem" : ""
      this.sufixoTarget.style.display = "none"
      this.campoWrapperTarget.innerHTML = `
        <div class="input-group" style="width: 120px;">
          <input type="number" step="0.01" class="form-control form-control-sm"
                name="az_mapa[resultado]" data-resultado-target="campo"
                placeholder="0">
          <span class="input-group-text">%</span>
        </div>
      `
    }
  }

  montarSelectHorasMinutos() {
    // Opções de horas
    let horasOptions = '<option value="">HH</option>'
    for (let h = 0; h <= 23; h++) horasOptions += `<option value="${h}">${h}</option>`

    // Opções de minutos (0 a 59)
    let minutosOptions = '<option value="">MM</option>'
    for (let m = 0; m < 60; m++) minutosOptions += `<option value="${m}">${m.toString().padStart(2, "0")}</option>`

    // Monta o wrapper com input group
    this.campoWrapperTarget.innerHTML = `
      <div class="d-flex gap-1 align-items-center">
        <select data-resultado-target="campoHora" class="form-select form-select-sm">${horasOptions}</select>
        <select data-resultado-target="campoMinuto" class="form-select form-select-sm">${minutosOptions}</select>
      </div>
    `

    // Listeners para atualizar decimal
    this.campoHoraTarget.addEventListener("change", () => this.atualizarTempo())
    this.campoMinutoTarget.addEventListener("change", () => this.atualizarTempo())
  }

  atualizarTempo() {
    const h = parseInt(this.campoHoraTarget.value || 0)
    const m = parseInt(this.campoMinutoTarget.value || 0)
    this.sufixoTarget.textContent = `${h}:${m.toString().padStart(2, "0")} h`

    // transforma em número decimal para enviar no form
    const decimal = h + m / 60
    // adiciona hidden input para enviar
    if (!this.hiddenInput) {
      this.hiddenInput = document.createElement("input")
      this.hiddenInput.type = "hidden"
      this.hiddenInput.name = "az_mapa[resultado]"
      this.campoWrapperTarget.appendChild(this.hiddenInput)
    }
    this.hiddenInput.value = decimal
  }
}
