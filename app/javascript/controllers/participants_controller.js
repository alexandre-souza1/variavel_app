import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "row", "source", "sector", "sectorField"]

  connect() {
    this.toggleSector()
  }

  add(event) {
    event.preventDefault()
    const row = this.rowTarget.cloneNode(true)
    row.querySelector("input").value = ""
    this.listTarget.appendChild(row)
    row.querySelector("input").focus()
  }

  remove(event) {
    event.preventDefault()
    const row = event.currentTarget.closest("[data-participants-target='row']")
    if (this.rowTargets.length === 1) {
      row.querySelector("input").value = ""
      return
    }

    row.remove()
  }

  toggleSector() {
    const isSector = this.sourceTarget.value === "users_by_sector"
    this.sectorTarget.disabled = !isSector
    this.sectorFieldTarget.hidden = !isSector
  }
}
