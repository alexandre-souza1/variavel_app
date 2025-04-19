import { Controller } from "stimulus"

export default class extends Controller {
  static targets = ["alert"]

  connect() {
    // Espera 3 segundos (3000ms) e depois remove a classe "show" para fazer o alerta desaparecer
    setTimeout(() => {
      this.hideAlert()
    }, 3000)  // 3000ms = 3 segundos
  }

  hideAlert() {
    this.alertTarget.classList.remove("show")
    this.alertTarget.classList.add("fade")
  }
}
