import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "fileField",
    "urlField",
    "fileInput",
    "urlInput"
  ]

  connect() {
    const selected = this.element.querySelector(
      'input[name="download_source"]:checked'
    )

    this.updateVisibility(selected?.value || null)
  }

  toggleSource(event) {
    this.updateVisibility(event.currentTarget.value)
  }

  updateVisibility(source) {
    const isFile = source === "file"
    const isUrl = source === "url"

    // Mostra/esconde os blocos
    this.fileFieldTarget.classList.toggle("d-none", !isFile)
    this.urlFieldTarget.classList.toggle("d-none", !isUrl)

    // Habilita somente o campo selecionado
    this.fileInputTarget.disabled = !isFile
    this.urlInputTarget.disabled = !isUrl

    // Torna obrigatório apenas o campo selecionado
    this.fileInputTarget.required = isFile
    this.urlInputTarget.required = isUrl
  }
}
