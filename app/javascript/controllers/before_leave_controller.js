import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {

    this.hasChanges = false
    this.isSubmitting = false

    this.element.addEventListener(
      "change",
      () => {
        this.hasChanges = true
      }
    )

    this.element.addEventListener(
      "input",
      () => {
        this.hasChanges = true
      }
    )

    this.element.addEventListener(
      "submit",
      (event) => {
        if (event.defaultPrevented) return

        this.isSubmitting = true
        this.hasChanges = false
      }
    )

    window.addEventListener(
      "beforeunload",
      this.beforeUnload
    )
  }

  disconnect() {

    window.removeEventListener(
      "beforeunload",
      this.beforeUnload
    )

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
