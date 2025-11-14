import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["required", "photo", "nokComment"]

  validate(event) {
    let valid = true

    // Remove erros antigos
    this.element.querySelectorAll(".text-danger").forEach(el => el.remove())

    // Campos obrigatórios simples
    this.requiredTargets.forEach(field => {
      if (field.disabled) return
      if (field.value.trim() === "") {
        valid = false
        this.addError(field, "Este campo é obrigatório")
      }
    })

    // Fotos obrigatórias
    this.photoTargets.forEach(input => {
      if (!input.disabled && input.files.length === 0) {
        valid = false
        this.addError(input, "Envie esta foto")
      }
    })

    // Comentários obrigatórios quando for NOK
    this.nokCommentTargets.forEach(comment => {
      if (!comment.disabled && comment.value.trim() === "") {
        valid = false
        this.addError(comment, "Explique o motivo do NOK")
      }
    })

    if (!valid) {
      event.preventDefault()
      // Rolando para o primeiro erro
      const firstError = this.element.querySelector('.text-danger')
      if (firstError) {
        firstError.scrollIntoView({ behavior: 'smooth', block: 'center' })
      }
    }
  }

  addError(element, message) {
    const div = document.createElement("div")
    div.classList.add("text-danger", "mt-1", "small")
    div.innerText = message
    element.parentNode.appendChild(div)
  }
}
