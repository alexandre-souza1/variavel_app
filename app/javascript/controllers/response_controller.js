import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["details", "photoInput", "commentInput"]

  connect() {
    console.log("Controller conectado para:", this.element)
  }

  showDetails() {
    this.detailsTarget.classList.remove("d-none")

    if (this.hasPhotoInputTarget) this.photoInputTarget.disabled = false
    if (this.hasCommentInputTarget) this.commentInputTarget.disabled = false
  }

  hideDetails() {
    this.detailsTarget.classList.add("d-none")

    if (this.hasPhotoInputTarget) this.photoInputTarget.disabled = true
    if (this.hasCommentInputTarget) this.commentInputTarget.disabled = true

    if (this.hasCommentInputTarget) this.commentInputTarget.value = ""
    if (this.hasPhotoInputTarget) this.photoInputTarget.value = null
  }

  // 🔧 Marcar tudo como OK
  markAllOk(event) {
    event.preventDefault()
    const okRadios = document.querySelectorAll('input[type="radio"][value="ok"]')

    okRadios.forEach(radio => {
      radio.checked = true
      radio.dispatchEvent(new Event("change"))
    })

    alert("Todos os itens foram marcados como OK ✅")
  }

  // 🆕 Marcar tudo como N/A
  markAllNa(event) {
    event.preventDefault()
    const naRadios = document.querySelectorAll('input[type="radio"][value="na"]')

    naRadios.forEach(radio => {
      radio.checked = true
      radio.dispatchEvent(new Event("change"))
    })

    alert("Todos os itens foram marcados como N/A ⚙️")
  }
}
