import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "icon"]

  toggle() {
    if (this.hasListTarget) {
      this.listTarget.classList.toggle("d-none")
    }

    if (this.hasIconTarget) {
      this.iconTarget.textContent =
        this.iconTarget.textContent === "▼" ? "▲" : "▼"
    }
  }
}