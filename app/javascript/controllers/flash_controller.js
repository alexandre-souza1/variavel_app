import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["alert"]

  connect() {
    setTimeout(() => {
      this.hideAlert()
    }, 3000)
  }

  hideAlert() {
    this.alertTarget.classList.remove("show")

    setTimeout(() => {
      this.element.remove()
    }, 150) // tempo da animação do Bootstrap
  }
}
