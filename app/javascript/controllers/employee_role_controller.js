import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sector", "cargo", "du", "az"]

  connect() { this.update() }

  update() {
    const sector = this.sectorTarget.value
    for (const option of this.cargoTarget.options) {
      const visible = (option.dataset.sectors || "").split(" ").includes(sector)
      option.hidden = !visible
      option.disabled = !visible
    }
    if (this.cargoTarget.selectedOptions[0]?.disabled) {
      this.cargoTarget.value = Array.from(this.cargoTarget.options).find(option => !option.disabled)?.value || ""
    }
    this.cargoTarget.required = true
    for (const [group, visible] of [[this.duTargets, sector === "du"], [this.azTargets, sector === "az"]]) {
      for (const panel of group) {
        panel.hidden = !visible
        for (const input of panel.querySelectorAll("input, select")) {
          input.disabled = !visible
          input.required = visible
        }
      }
    }
  }
}
