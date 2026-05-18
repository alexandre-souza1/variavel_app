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

  addPhoto(event) {
    const content =
      this.templateTarget.innerHTML.replaceAll(
        "NEW_RECORD",
        this.indexValue
      )

    event.target.insertAdjacentHTML(
      "beforebegin",
      content
    )

    this.indexValue++
  }

  removePhoto(event) {
    const card =
      event.target.closest(".card")

    const destroyInput =
      card.querySelector('input[name$="[_destroy]"]')

    const idInput =
      card.querySelector('input[name$="[id]"]')

    if (destroyInput && idInput) {
      destroyInput.value = "1"
      card.classList.add("d-none")
    } else {
      card.remove()
    }
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

  addDefect(event) {
    const template = this.defectTemplateTarget.innerHTML
    const content = template.replace(/NEW_DEFECT/g, Date.now())

    event.target.insertAdjacentHTML(
      "beforebegin",
      content
    )
  }

  removeDefect(event) {
    const card =
      event.target.closest(".border")

    const destroyInput =
      card.querySelector('input[name$="[_destroy]"]')

    const idInput =
      card.querySelector('input[name$="[id]"]')

    if (destroyInput && idInput) {
      destroyInput.value = "1"
      card.classList.add("d-none")
    } else {
      card.remove()
    }
  }
}
