import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.loaded = false
    this.loading = false
    this.tooltip = new bootstrap.Tooltip(this.element, { container: "body", trigger: "hover focus" })
  }

  async load() {
    if (this.loaded || this.loading) return

    this.loading = true
    this.request = new AbortController()
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
        signal: this.request.signal
      })
      if (!response.ok) throw new Error("Inspection unavailable")

      const result = await response.json()
      this.updateTooltip(result.message)
      this.loaded = true
    } catch (error) {
      if (error.name !== "AbortError") {
        this.updateTooltip("Não foi possível consultar a última aferição de sulcos no Prolog.")
      }
    } finally {
      this.loading = false
    }
  }

  updateTooltip(message) {
    this.element.setAttribute("aria-description", message)
    this.tooltip.setContent({ ".tooltip-inner": message })
  }

  disconnect() {
    this.request?.abort()
    this.tooltip.dispose()
  }
}
