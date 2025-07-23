import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "previewContainer"]

  openFileDialog() {
    this.inputTarget.click()
  }

  preview() {
    const file = this.inputTarget.files[0]
    if (!file) return

    const reader = new FileReader()
    reader.onload = (event) => {
      this.previewTarget?.remove()
      this.previewContainerTarget.innerHTML = `
        <img src="${event.target.result}"
             class="rounded-circle border mb-2"
             width="150"
             height="150"
             data-photo-preview-target="preview">
      `
    }
    reader.readAsDataURL(file)
  }
}
