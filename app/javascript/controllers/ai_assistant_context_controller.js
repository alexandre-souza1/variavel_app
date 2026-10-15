import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  static values = { page: Object }

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    const announce = () => window.dispatchEvent(new CustomEvent("ai-assistant:context", { detail: { page: this.pageValue } }))
    const element = this.element.closest(".modal")
    const modal = element && Modal.getInstance(element)
    if (modal && element.classList.contains("show")) {
      element.addEventListener("hidden.bs.modal", announce, { once: true })
      modal.hide()
    } else {
      announce()
    }
  }
}
