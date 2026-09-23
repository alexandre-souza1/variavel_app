import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["grid", "option"]
  static values = { storageKey: String }

  connect() {
    let columns = "3"
    try {
      columns = localStorage.getItem(this.storageKeyValue) || columns
    } catch (_) {
      // A seleção continua disponível quando o navegador bloqueia o armazenamento.
    }
    this.apply(columns)
  }

  change(event) {
    const columns = event.currentTarget.dataset.columns
    this.apply(columns)
    try {
      localStorage.setItem(this.storageKeyValue, columns)
    } catch (_) {
      // Mantém a escolha nesta página mesmo sem persistência local.
    }
  }

  apply(value) {
    const columns = value === "2" ? "2" : "3"
    this.gridTarget.style.setProperty("--fleet-grid-columns", columns)
    this.optionTargets.forEach((button) => {
      const selected = button.dataset.columns === columns
      button.classList.toggle("active", selected)
      button.setAttribute("aria-pressed", String(selected))
    })
  }
}
