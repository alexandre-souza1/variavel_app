import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["group", "fixed"]

  connect() { this.update() }

  update() {
    const fixed = this.groupTarget.value === "FIXO"
    this.fixedTargets.forEach(field => {
      field.hidden = !fixed
      field.querySelectorAll("select").forEach(input => { input.disabled = !fixed })
    })
  }
}
