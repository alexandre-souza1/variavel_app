import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["details", "photoInput", "commentInput"]

  connect() {
    console.log("Controller conectado para:", this.element)
  }

  showDetails() {
    console.log("Mostrando detalhes para:", this.element)
    this.detailsTarget.classList.remove("d-none")

    // habilita os campos quando o usuário marca NOK
    if (this.hasPhotoInputTarget) this.photoInputTarget.disabled = false
    if (this.hasCommentInputTarget) this.commentInputTarget.disabled = false
  }

  hideDetails() {
    console.log("Ocultando detalhes para:", this.element)
    this.detailsTarget.classList.add("d-none")

    // desabilita os campos quando o usuário marca OK
    if (this.hasPhotoInputTarget) this.photoInputTarget.disabled = true
    if (this.hasCommentInputTarget) this.commentInputTarget.disabled = true

    // limpa os valores (opcional, mas evita envio acidental)
    if (this.hasCommentInputTarget) this.commentInputTarget.value = ""
    if (this.hasPhotoInputTarget) this.photoInputTarget.value = null
  }
}
