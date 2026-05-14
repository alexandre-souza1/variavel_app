import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "container",
    "template",
    "defectsContainer",
    "defectTemplate"
  ]

  static values = {
    index: Number
  }

  addPhoto() {
    const content =
      this.templateTarget.innerHTML.replaceAll(
        "NEW_RECORD",
        this.indexValue
      )

    this.containerTarget.insertAdjacentHTML(
      "beforeend",
      content
    )

    this.indexValue++
  }

  removePhoto(event) {
    event.target.closest(".card").remove()
  }

  previewImage(event) {
    const input = event.target
    const file = input.files[0]

    if (!file) return

    const reader = new FileReader()

    reader.onload = (e) => {
      this.previewTarget.src = e.target.result
      this.previewTarget.classList.remove("d-none")
    }

    reader.readAsDataURL(file)
  }

  addDefect() {
    const template = this.defectTemplateTarget.innerHTML
    const content = template.replace(/NEW_DEFECT/g, Date.now())

    this.defectsContainerTarget.insertAdjacentHTML(
      "beforeend",
      content
    )
  }
}