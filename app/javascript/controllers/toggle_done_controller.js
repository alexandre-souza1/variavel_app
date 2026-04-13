import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "icon"]

  toggle() {
    this.listTarget.classList.toggle("d-none")

    if (this.listTarget.classList.contains("d-none")) {
      this.iconTarget.innerText = "▼"
    } else {
      this.iconTarget.innerText = "▲"
    }
  }
}