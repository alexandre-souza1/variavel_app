import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["description"]

  generate(event) {
    event.preventDefault()
    this.descriptionTarget.value = this.descriptionTarget.value.trim()
    if (!this.descriptionTarget.reportValidity()) return
    const question = "Crie uma nova automação a partir desta descrição. Aproveite os dados informados e pergunte somente o que faltar:\n\n" + this.descriptionTarget.value
    window.dispatchEvent(new CustomEvent("ai-assistant:automation", { detail: { question } }))
  }
};
