import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["error"]
  static values = { url: String }

  async connect() {
    this.request = new AbortController()
    this.element.setAttribute("aria-busy", "true")
    try {
      const response = await fetch(this.urlValue, {
        headers: { "Turbo-Frame": this.element.id, Accept: "text/html" },
        signal: this.request.signal
      })
      if (!this.element.isConnected) return
      if (response.redirected) { Turbo.visit(response.url); return }

      const html = new DOMParser().parseFromString(await response.text(), "text/html")
      const frame = html.getElementById(this.element.id)
      if (!frame) throw new Error("Resposta sem o relatório solicitado")

      // O stream também ativa os scripts dos gráficos e os seletores inseridos.
      Turbo.renderStreamMessage(`<turbo-stream action="update" target="${this.element.id}"><template>${frame.innerHTML}</template></turbo-stream>`)
    } catch (error) {
      if (error.name !== "AbortError" && this.element.isConnected && this.hasErrorTarget) {
        this.element.innerHTML = this.errorTarget.innerHTML
      }
    } finally {
      this.element.removeAttribute("aria-busy")
    }
  }

  disconnect() {
    this.request?.abort()
  }
}
