import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "backdrop", "openButton"]
  static values = { open: Boolean }

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
    if (this.openValue) this.open()
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  open() {
    this.panelTarget.classList.add("is-open")
    this.backdropTarget.classList.add("is-visible")
    this.panelTarget.setAttribute("aria-hidden", "false")
    this.openButtonTarget.setAttribute("aria-expanded", "true")
    document.body.classList.add("public-variable-chat-is-open")
    this.panelTarget.querySelector("textarea, select, input")?.focus()
  }

  close() {
    this.panelTarget.classList.remove("is-open")
    this.backdropTarget.classList.remove("is-visible")
    this.panelTarget.setAttribute("aria-hidden", "true")
    this.openButtonTarget.setAttribute("aria-expanded", "false")
    document.body.classList.remove("public-variable-chat-is-open")
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.panelTarget.classList.contains("is-open")) this.close()
  }
}
