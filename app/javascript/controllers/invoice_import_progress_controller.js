import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { statusUrl: String, notificationId: String }

  connect() {
    this.render("Importação iniciada", "Consultando os e-mails de abastecimento...", false)
    this.poll()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  async dismiss(event) {
    event.preventDefault()
    clearTimeout(this.timer)

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    try {
      await fetch(`/notifications/${this.notificationIdValue}`, {
        method: "DELETE",
        headers: {
          Accept: "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        credentials: "same-origin"
      })
    } finally {
      document.getElementById("invoice-import-progress-toast")?.remove()
    }
  }

  async poll() {
    try {
      const response = await fetch(this.statusUrlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error("Não foi possível consultar o progresso")
      const data = await response.json()
      this.render(data.title, data.body, data.finished)
      if (!data.finished) this.timer = setTimeout(() => this.poll(), 1200)
    } catch (error) {
      this.render("Importação em andamento", "O processamento continua no servidor.", false)
      this.timer = setTimeout(() => this.poll(), 3000)
    }
  }

  render(title, body, finished) {
    let toast = document.getElementById("invoice-import-progress-toast")
    if (!toast) {
      toast = document.createElement("div")
      toast.id = "invoice-import-progress-toast"
      toast.className = "position-fixed bottom-0 end-0 m-4 p-3 bg-body border rounded-3 shadow"
      toast.style.zIndex = "1080"
      document.body.appendChild(toast)
    }
    toast.replaceChildren()
    const header = document.createElement("div")
    header.className = "d-flex justify-content-between align-items-start gap-3"
    const titleElement = document.createElement("div")
    titleElement.className = "fw-semibold mb-1"
    titleElement.textContent = title
    const close = document.createElement("button")
    close.type = "button"
    close.className = "btn-close"
    close.setAttribute("aria-label", "Apagar notificação")
    close.title = "Apagar notificação"
    close.addEventListener("click", (event) => this.dismiss(event))
    header.append(titleElement, close)
    const bodyElement = document.createElement("div")
    bodyElement.className = "small text-muted mb-2"
    bodyElement.textContent = body
    const progress = document.createElement("div")
    progress.className = "progress"
    progress.setAttribute("role", "progressbar")
    const bar = document.createElement("div")
    bar.className = "progress-bar progress-bar-striped progress-bar-animated"
    bar.style.width = finished ? "100%" : "65%"
    progress.appendChild(bar)
    toast.append(header, bodyElement, progress)
    if (finished) {
      bar.classList.remove("progress-bar-animated")
      setTimeout(() => toast.remove(), 7000)
    }
  }
}
