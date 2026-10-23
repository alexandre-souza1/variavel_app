import { Controller } from "@hotwired/stimulus"
import { Offcanvas } from "bootstrap"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["panel", "frame"]
  static values = { url: String, open: Boolean }

  connect() {
    if (!this.hasPanelTarget) return
    this.drawer = Offcanvas.getOrCreateInstance(this.panelTarget)
    if (this.openValue) {
      this.openValue = false
      this.open()
      const url = new URL(window.location.href)
      url.searchParams.delete("settings")
      window.history.replaceState(window.history.state, "", url)
    }
  }

  disconnect() { this.drawer?.dispose() }

  open(event) {
    event?.preventDefault()
    if (!this.drawer) return
    const url = new URL(this.urlValue, window.location.origin)
    new URL(window.location.href).searchParams.forEach((value, key) => url.searchParams.set(`context[${key}]`, value))
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = '<p class="text-muted" role="status"><span class="spinner-border spinner-border-sm me-2" aria-hidden="true"></span>Carregando planos…</p>'
    this.frameTarget.src = url.toString()
    this.drawer.show(event?.currentTarget)
  }

  loaded() {
    const saved = this.frameTarget.querySelector("[data-settings-saved-url]")
    if (!saved) return
    const visit = () => Turbo.visit(saved.dataset.settingsSavedUrl, { action: "replace" })
    if (!this.panelTarget.classList.contains("show")) {
      visit()
      return
    }
    this.panelTarget.addEventListener("hidden.bs.offcanvas", visit, { once: true })
    this.drawer.hide()
  }

  saving() { this.panelTarget.setAttribute("aria-busy", "true") }

  saved() { this.panelTarget.removeAttribute("aria-busy") }

  missing(event) {
    event.preventDefault()
    this.frameTarget.innerHTML = '<p class="alert alert-danger m-3" role="alert">Não foi possível carregar as configurações. Feche o painel e tente novamente.</p>'
  }

  beforeCache() {
    if (!this.drawer) return
    this.drawer.hide()
    this.panelTarget.classList.remove("show", "showing", "hiding")
    this.frameTarget.removeAttribute("src")
    this.frameTarget.replaceChildren()
    document.querySelectorAll(".offcanvas-backdrop").forEach(element => element.remove())
  }
}
