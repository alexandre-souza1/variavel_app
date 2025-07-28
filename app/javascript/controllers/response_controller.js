import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["details"]

  connect() {
    console.log("Controller conectado para:", this.element)
  }

  showDetails() {
    console.log("Mostrando detalhes para:", this.element)
    this.detailsTarget.classList.remove("d-none")
  }

  hideDetails() {
    console.log("Ocultando detalhes para:", this.element)
    this.detailsTarget.classList.add("d-none")
  }
}
