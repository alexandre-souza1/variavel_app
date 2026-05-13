import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "preview",
    "kind",
    "descriptionContainer"
  ]

  connect() {
    this.toggleDescription()
  }

  preview(event) {
    const file = event.target.files[0]

    if (!file) return

    const reader = new FileReader()

    reader.onload = (e) => {
      this.previewTarget.src = e.target.result
      this.previewTarget.classList.remove("d-none")
    }

    reader.readAsDataURL(file)
  }

  toggleDescription() {
    const isDefect =
      this.kindTarget.value === "defect"

    this.descriptionContainerTarget
      .classList.toggle("d-none", !isDefect)
  }
}