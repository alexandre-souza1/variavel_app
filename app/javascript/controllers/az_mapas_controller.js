import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["metaSelect", "turnoDisplay"]

  connect() {
    this.updateTurno()
  }

  updateTurno() {
    const meta = this.metaSelectTarget.value

    const turnosPorMeta = {
      "tempo_atendimento": "A/B/C",
      "eficiencia_carregamento": "A/C",
      "eficiencia_descarga": "B"
    }

    this.turnoDisplayTarget.textContent = turnosPorMeta[meta] || "-"
  }
}
