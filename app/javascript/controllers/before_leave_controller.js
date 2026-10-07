import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {

    this.hasChanges = false
    this.isSubmitting = false

    this.element.addEventListener("change", this.markAsChanged)
    this.element.addEventListener("input", this.markAsChanged)
    this.element.addEventListener("submit", this.beforeSubmit)
    this.element.addEventListener("allow-leave", this.allowLeave)
    document.addEventListener("turbo:before-visit", this.beforeVisit)

    window.addEventListener(
      "beforeunload",
      this.beforeUnload
    )
  }

  disconnect() {

    this.element.removeEventListener("change", this.markAsChanged)
    this.element.removeEventListener("input", this.markAsChanged)
    this.element.removeEventListener("submit", this.beforeSubmit)
    this.element.removeEventListener("allow-leave", this.allowLeave)
    document.removeEventListener("turbo:before-visit", this.beforeVisit)

    window.removeEventListener(
      "beforeunload",
      this.beforeUnload
    )

  }

  markAsChanged = () => {
    this.hasChanges = true
  }

  beforeSubmit = (event) => {
    if (event.defaultPrevented) return

    this.isSubmitting = true
    this.hasChanges = false
  }

  allowLeave = () => {
    this.hasChanges = false
  }

  beforeVisit = (event) => {
    if (event.defaultPrevented || this.isSubmitting || !this.hasChanges) return

    if (!window.confirm("Há alterações neste checklist que ainda não foram salvas. Deseja sair?")) {
      event.preventDefault()
      return
    }

    this.allowLeave()
  }

  beforeUnload = (event) => {

    if (this.isSubmitting) return
    if (!this.hasChanges) return

    event.preventDefault()

    event.returnValue = ""

  }

  markAsSaved() {
    this.hasChanges = false
  }
}
