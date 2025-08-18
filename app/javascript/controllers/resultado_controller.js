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
      // Número normal
      this.unidadeTarget.textContent = tipo.includes("eficiencia") ? "Informe a porcentagem" : ""
      this.sufixoTarget.textContent = tipo.includes("eficiencia") ? "%" : ""
      this.campoWrapperTarget.innerHTML = `<input type="number" step="0.01" class="form-control" data-resultado-target="campo">`
    }
  }

  montarSelectHorasMinutos() {
    // Monta HTML dos selects
    let horasOptions = '<option value="">HH</option>'
    for (let h = 0; h <= 23; h++) horasOptions += `<option value="${h}">${h}</option>`

    let minutosOptions = '<option value="">MM</option>'
    for (let m = 0; m < 60; m += 5) minutosOptions += `<option value="${m}">${m.toString().padStart(2, "0")}</option>`

    this.campoWrapperTarget.innerHTML = `
      <select data-resultado-target="campoHora" class="form-select me-1">${horasOptions}</select>
      <select data-resultado-target="campoMinuto" class="form-select">${minutosOptions}</select>
    `

    // adiciona listener para atualizar sufixo
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
