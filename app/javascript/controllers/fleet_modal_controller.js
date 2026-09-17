import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  static values = { open: Boolean }

  connect() {
    if (!this.openValue) return

    this.modal = Modal.getOrCreateInstance(this.element)
    this.modal.show()
  }
}
