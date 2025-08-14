import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }
  static targets = ["button"]

  copy(event) {
    event.preventDefault()

    navigator.clipboard.writeText(this.textValue)
      .then(() => this.showCopiedState())
      .catch(() => this.showErrorState())
  }

  showCopiedState() {
    this.originalText = this.buttonTarget.textContent
    this.originalClasses = this.buttonTarget.className

    this.buttonTarget.textContent = "Link copiado!"
    this.buttonTarget.className = "btn btn-sm btn-success"

    setTimeout(() => this.resetButton(), 2000)
  }

  showErrorState() {
    this.originalText = this.buttonTarget.textContent
    this.originalClasses = this.buttonTarget.className

    this.buttonTarget.textContent = "Erro ao copiar"
    this.buttonTarget.className = "btn btn-sm btn-danger"

    setTimeout(() => this.resetButton(), 2000)
  }

  resetButton() {
    this.buttonTarget.textContent = this.originalText
    this.buttonTarget.className = this.originalClasses
  }
}
