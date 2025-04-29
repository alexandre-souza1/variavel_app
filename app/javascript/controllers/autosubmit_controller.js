import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "form"]

  connect() {
    // Opcional: debug para verificar se o controller está conectado
    console.log("Autosubmit controller connected")
  }

  submitOnChange() {
    if (this.selectTarget.value) {
      this.formTarget.submit()
    }
  }
}
