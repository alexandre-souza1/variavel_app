import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  static values = { open: Boolean }

  connect() {
    this.modal = Modal.getOrCreateInstance(this.element)
    if (this.openValue) this.modal.show()
  }

  focus() {
    this.element.querySelector(".alert-danger")?.focus()
    if (!this.element.querySelector(".alert-danger")) {
      this.element.querySelector('input:not([type="hidden"]):not([type="checkbox"])')?.focus()
    }
  }

  beforeCache() {
    this.modal?.hide()
  }

  disconnect() {
    this.modal?.dispose()
  }
}
