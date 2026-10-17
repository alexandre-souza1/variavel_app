import { Controller } from "@hotwired/stimulus"
import { Offcanvas } from "bootstrap"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["panel", "frame", "title", "trigger"]

  connect() {
    this.drawer = Offcanvas.getOrCreateInstance(this.panelTarget)
    this.triggerTargets.forEach(button => { button.disabled = false })
    this.beforeCache = () => {
      this.triggerTargets.forEach(button => { button.disabled = true })
      this.drawer.hide()
      this.panelTarget.classList.remove("show", "showing", "hiding")
      document.querySelectorAll(".offcanvas-backdrop").forEach(element => element.remove())
    }
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.drawer.dispose()
  }

  open(event) {
    event.preventDefault()
    const url = event.currentTarget.dataset.drawerUrl
    this.titleTarget.textContent = event.currentTarget.dataset.drawerTitle || "Nova automação"
    if (this.formUrl === url && this.frameTarget.querySelector("form")) {
      this.drawer.show(event.currentTarget)
      return
    }
    this.formUrl = url
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = '<p class="automation-help" role="status">Carregando formulário…</p>'
    this.frameTarget.src = url
    this.drawer.show(event.currentTarget)
  }

  loaded() {
    const saved = this.frameTarget.querySelector("[data-automation-saved-url]")
    if (saved) {
      this.navigate(saved.dataset.automationSavedUrl)
      return
    }
    const preview = this.frameTarget.querySelector("#automation-preview")
    const error = this.frameTarget.querySelector('[role="alert"]')
    ;(error || preview)?.scrollIntoView({ block: "nearest" })
  }

  redirected(event) {
    if (!event.detail.response.redirected) return
    event.preventDefault()
    this.navigate(event.detail.response.url)
  }

  navigate(url) {
    if (!this.panelTarget.classList.contains("show")) {
      Turbo.visit(url)
      return
    }
    this.panelTarget.addEventListener("hidden.bs.offcanvas", () => Turbo.visit(url), { once: true })
    this.drawer.hide()
  }
};
