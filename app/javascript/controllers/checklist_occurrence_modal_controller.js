import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  static targets = ["container"]
  static values = { detailsUrl: String }

  disconnect() { this.close() }

  async open(event) {
    if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    if (this.modal) return
    const link = event.currentTarget
    const url = new URL(link.href)
    url.pathname = this.detailsUrlValue
    url.hash = ""
    this.modalUrl = url.toString()
    const controller = new AbortController()
    this.loadController = controller
    this.containerTarget.innerHTML = `
      <div class="modal fade app-modal checklist-tracking-modal" id="checklistOccurrencesModal" tabindex="-1" aria-labelledby="checklistOccurrencesModalTitle" aria-hidden="true">
        <div class="modal-dialog modal-xl modal-dialog-centered modal-dialog-scrollable">
          <div class="modal-content">
            <div class="modal-header">
              <h2 class="modal-title fs-5" id="checklistOccurrencesModalTitle">Ocorrências</h2>
              <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Fechar"></button>
            </div>
            <div class="modal-body" aria-busy="true">
              <p role="status"><span class="spinner-border spinner-border-sm me-2" aria-hidden="true"></span>Carregando ocorrências…</p>
            </div>
          </div>
        </div>
      </div>`
    const element = this.containerTarget.querySelector(".modal")
    const modal = new Modal(element)
    this.modal = modal
    element.addEventListener("hidden.bs.modal", () => {
      controller.abort()
      modal.dispose()
      this.modal = null
      this.containerTarget.replaceChildren()
      if (link.isConnected) link.focus()
    }, { once: true })
    modal.show()
    try {
      const response = await fetch(url, { headers: { Accept: "text/html" }, signal: controller.signal })
      if (!response.ok) throw new Error("Não foi possível abrir as ocorrências.")
      const page = new DOMParser().parseFromString(await response.text(), "text/html")
      const content = page.querySelector(".modal-content")
      if (!content) throw new Error("Não foi possível abrir as ocorrências.")
      if (controller.signal.aborted) return
      element.querySelector(".modal-content").replaceWith(content)
      modal.handleUpdate()
    } catch (error) {
      if (controller.signal.aborted) return
      const body = element.querySelector(".modal-body")
      body.removeAttribute("aria-busy")
      body.replaceChildren()
      this.showMessage(body, error.message, "danger")
      const fallback = document.createElement("a")
      fallback.href = link.href
      fallback.textContent = "Abrir histórico"
      body.append(fallback)
    }
  }

  async exclude(event) {
    event.preventDefault()
    const form = event.currentTarget
    const button = form.querySelector('[type="submit"]')
    if (button.disabled) return
    const originalLabel = button.value
    button.disabled = true
    button.value = "Salvando…"
    form.setAttribute("aria-busy", "true")
    form.querySelector('[role="alert"]')?.remove()
    const modalUrl = this.modalUrl
    let saved = false
    try {
      const data = new FormData(form)
      this.appendFilters(data, "dashboard", window.location.href)
      this.appendFilters(data, "modal", modalUrl)
      const response = await fetch(form.action, {
        method: "PATCH", body: data,
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      })
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Não foi possível salvar a justificativa.")
      saved = true
      this.refresh(result, modalUrl)
    } catch (error) {
      const message = saved ? "Justificativa salva. Recarregue a página para atualizar os totais." : error.message
      const target = form.isConnected ? form : this.containerTarget.querySelector(".modal-body")
      if (target) this.showMessage(target, message, saved ? "warning" : "danger")
    } finally {
      form.removeAttribute("aria-busy")
      if (button.isConnected) {
        button.disabled = false
        button.value = originalLabel
      }
    }
  }

  appendFilters(data, name, href) {
    const filters = new URL(href).searchParams
    data.set(`${name}[display]`, filters.get("display") || "annual")
    filters.forEach((value, key) => data.set(`${name}[${key}]`, value))
  }

  refresh(result, modalUrl) {
    const parser = new DOMParser()
    for (const [id, html] of Object.entries(result.fragments)) {
      const next = parser.parseFromString(html, "text/html").getElementById(id)
      const current = this.element.querySelector(`#${id}`)
      if (next && current) current.replaceWith(next)
    }
    const content = this.containerTarget.querySelector(".modal-content")
    // The user can close the modal while the save request is in flight.
    if (!content || this.modalUrl !== modalUrl) return
    this.loadController?.abort()
    const scroll = content.querySelector(".modal-body").scrollTop
    const next = parser.parseFromString(result.modal, "text/html").querySelector(".modal-content")
    content.replaceChildren(...next.childNodes)
    const body = content.querySelector(".modal-body")
    this.showMessage(body, result.message, "success")
    body.scrollTop = scroll
    this.modal?.handleUpdate()
  }

  showMessage(target, message, type) {
    const alert = document.createElement("p")
    alert.className = `alert alert-${type}`
    alert.setAttribute("role", type === "success" ? "status" : "alert")
    alert.textContent = message
    target.prepend(alert)
  }

  close() {
    this.loadController?.abort()
    this.modal?.hide()
  }
}
