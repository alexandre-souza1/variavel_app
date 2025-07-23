// app/javascript/controllers/autonomy_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form"]

  connect() {
    console.log("Autonomy Form Controller connected")
  }

  validate(event) {
    if (!this.formTarget.checkValidity()) {
      event.preventDefault()
      event.stopPropagation()
    }

    this.formTarget.classList.add('was-validated')
  }
}
