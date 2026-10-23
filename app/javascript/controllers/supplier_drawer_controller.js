import { Controller } from "@hotwired/stimulus"
import { Offcanvas } from "bootstrap"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["panel", "frame", "title"]
  static values = { autoOpen: Boolean }

  connect() {
    this.drawer = Offcanvas.getOrCreateInstance(this.panelTarget)
    this.beforeCache = () => {
      if (!this.panelTarget.classList.contains("show") && !this.panelTarget.classList.contains("showing")) return
      this.navigating = true
      const backdrop = document.querySelector(".offcanvas-backdrop")
      this.drawer.hide()
      // Finish closing before Turbo snapshots the body and its scrollbar styles.
      this.panelTarget.dispatchEvent(new Event("transitionend"))
      backdrop?.dispatchEvent(new Event("transitionend"))
    }
    this.closed = () => {
      if (this.navigating) return
      this.frameTarget.removeAttribute("src")
      this.frameTarget.replaceChildren()
      if (this.autoOpenValue) history.replaceState(history.state, "", "/suppliers")
      this.autoOpenValue = false
      this.trigger?.focus()
    }
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.panelTarget.addEventListener("hidden.bs.offcanvas", this.closed)
    if (this.autoOpenValue) this.drawer.show()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.panelTarget.removeEventListener("hidden.bs.offcanvas", this.closed)
    this.drawer.dispose()
  }

  open(event) {
    event.preventDefault()
    this.trigger = event.currentTarget
    this.titleTarget.textContent = this.trigger.dataset.drawerTitle
    this.frameTarget.removeAttribute("src")
    const loading = document.createElement("p")
    loading.className = "supplier-drawer__loading"
    loading.setAttribute("role", "status")
    loading.textContent = "Carregando formulário…"
    this.frameTarget.replaceChildren(loading)
    this.frameTarget.src = this.trigger.href
    this.drawer.show(this.trigger)
  }

  loaded() {
    const saved = this.frameTarget.querySelector("[data-supplier-saved-url]")
    if (saved) return this.navigate(saved.dataset.supplierSavedUrl)
    this.frameTarget.querySelector('[role="alert"]')?.scrollIntoView({ block: "nearest" })
  }

  missing(event) {
    event.preventDefault()
    if (event.detail.response.redirected) return this.navigate(event.detail.response.url)
    this.frameTarget.textContent = "Não foi possível abrir o formulário. Feche e tente novamente."
  }

  navigate(url) {
    this.navigating = true
    this.panelTarget.addEventListener("hidden.bs.offcanvas", () => Turbo.visit(url), { once: true })
    this.drawer.hide()
  }
}
