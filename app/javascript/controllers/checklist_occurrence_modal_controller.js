import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  static targets = ["container"]
  static values = { detailsUrl: String }

  disconnect() { this.close() }

  async open(event) {
    if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    const link = event.currentTarget
    const url = new URL(link.href)
    url.pathname = this.detailsUrlValue
    url.hash = ""
    try {
      const response = await fetch(url, { headers: { Accept: "text/html" } })
      if (!response.ok) throw new Error("Não foi possível abrir as ocorrências.")
      this.modalUrl = url.toString()
      this.containerTarget.innerHTML = await response.text()
      const element = this.containerTarget.querySelector(".modal")
      this.modal = new Modal(element)
      element.addEventListener("hidden.bs.modal", () => {
        this.modal?.dispose()
        this.modal = null
        this.containerTarget.replaceChildren()
        link.isConnected && link.focus()
      }, { once: true })
      this.modal.show()
    } catch (_error) {
      window.location.assign(link.href)
    }
  }

  async exclude(event) {
    event.preventDefault()
    const form = event.currentTarget
    const button = form.querySelector('[type="submit"]')
    button.disabled = true
    try {
      const response = await fetch(form.action, {
        method: "PATCH", body: new FormData(form),
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      })
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Não foi possível salvar a justificativa.")
      await this.refresh(result.message)
    } catch (error) {
      let alert = form.querySelector('[role="alert"]')
      if (!alert) {
        alert = document.createElement("p")
        alert.className = "alert alert-danger"
        alert.setAttribute("role", "alert")
        form.prepend(alert)
      }
      alert.textContent = error.message
    } finally {
      if (button.isConnected) button.disabled = false
    }
  }

  async refresh(message) {
    const [pageResponse, modalResponse] = await Promise.all([
      fetch(window.location.href, { headers: { Accept: "text/html" } }),
      fetch(this.modalUrl, { headers: { Accept: "text/html" } })
    ])
    if (!pageResponse.ok || !modalResponse.ok) throw new Error("Justificativa salva. Recarregue a página para atualizar os totais.")
    const parser = new DOMParser()
    const page = parser.parseFromString(await pageResponse.text(), "text/html")
    for (const selector of ["#tracking-navigation", "#tracking-summary", "#tracking-overview", "#tracking-history", "#tracking-review"]) {
      const next = page.querySelector(selector)
      const current = this.element.querySelector(selector)
      if (next && current) current.replaceWith(next)
    }
    const nextModal = parser.parseFromString(await modalResponse.text(), "text/html")
    const content = this.containerTarget.querySelector(".modal-content")
    const scroll = content.querySelector(".modal-body").scrollTop
    content.replaceChildren(...nextModal.querySelector(".modal-content").childNodes)
    const body = content.querySelector(".modal-body")
    const alert = document.createElement("p")
    alert.className = "alert alert-success"
    alert.setAttribute("role", "status")
    alert.textContent = message
    body.prepend(alert)
    body.scrollTop = scroll
  }

  close() { this.modal?.hide() }
}
