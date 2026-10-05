import { Controller } from "@hotwired/stimulus"

export function showFlash(message, { type = "info", url = null } = {}) {
  const container = document.getElementById("flash-container")
  if (!container) return

  const wrapper = document.createElement("div")
  wrapper.dataset.controller = "flash"
  const alert = document.createElement("div")
  alert.className = `alert alert-${type} alert-dismissible fade show m-1`
  alert.dataset.flashTarget = "alert"
  alert.setAttribute("role", "status")
  alert.appendChild(document.createTextNode(message))
  if (url) {
    const link = document.createElement("a")
    link.href = url
    link.className = "alert-link ms-1"
    link.textContent = "Ver tarefa"
    alert.appendChild(link)
  }
  const close = document.createElement("button")
  close.type = "button"
  close.className = "btn-close"
  close.setAttribute("aria-label", "Fechar")
  close.addEventListener("click", () => wrapper.remove())
  alert.appendChild(close)
  wrapper.appendChild(alert)
  container.appendChild(wrapper)
}

export default class extends Controller {
  static targets = ["alert"]

  connect() {
    this.hideTimeout = setTimeout(() => {
      this.hideAlert()
    }, 3000)
  }

  disconnect() {
    clearTimeout(this.hideTimeout)
    clearTimeout(this.removeTimeout)
  }

  hideAlert() {
    if (!this.hasAlertTarget) return

    this.alertTarget.classList.remove("show")

    this.removeTimeout = setTimeout(() => {
      this.element.remove()
    }, 150) // tempo da animação do Bootstrap
  }
}
