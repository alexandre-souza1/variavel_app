import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["current", "original", "editor"]

  toggle(event) {
    event.preventDefault()
    if (!this.hasOriginalTarget) return

    if (this.hasEditorTarget) this.editorTarget.classList.remove("is-open")
    this.currentTarget.classList.toggle("is-hidden")
    this.originalTarget.classList.toggle("is-hidden")
    event.currentTarget.setAttribute(
      "aria-pressed",
      String(!this.originalTarget.classList.contains("is-hidden"))
    )
  }

  edit(event) {
    event.preventDefault()
    this.currentTarget.classList.add("is-hidden")
    if (this.hasOriginalTarget) this.originalTarget.classList.add("is-hidden")
    this.editorTarget.classList.add("is-open")
  }

  cancel(event) {
    event.preventDefault()
    this.editorTarget.querySelector("form")?.reset()
    this.editorTarget.classList.remove("is-open")
    this.currentTarget.classList.remove("is-hidden")
    if (this.hasOriginalTarget) this.originalTarget.classList.add("is-hidden")
  }
}
