import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  connect() {
    this.validate() // garante que começa desabilitado
  }

  validate() {
    const value = this.inputTarget.value.trim()

    if (value === "EXCLUIR") {
      this.buttonTarget.removeAttribute("disabled")
    } else {
      this.buttonTarget.setAttribute("disabled", true)
    }
  }
}