import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["colors", "button", "buttonLabel", "icon", "status", "error", "dialog", "trigger", "form", "feedback", "swatches", "colorCount"]
  static values = { url: String, autoOpen: Boolean }

  connect() {
    this.alive = true
    this.previewPalette()
    if (this.autoOpenValue) {
      this.open()
      this.autoOpenValue = false
    }
  }

  disconnect() {
    this.alive = false
    this.abortController?.abort()
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.setBusy(false)
  }

  open() {
    this.errorTarget.hidden = true
    this.statusTarget.textContent = ""
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.colorsTarget.focus({ preventScroll: true })
  }

  close(event) {
    event?.preventDefault()
    this.abortController?.abort()
    this.abortController = null
    this.setBusy(false)
    this.hideDialog()
    this.triggerTarget.focus({ preventScroll: true })
  }

  hideDialog() {
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  backdrop(event) {
    if (event.target !== this.dialogTarget) return
    const box = this.dialogTarget.getBoundingClientRect()
    if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) this.close(event)
  }

  previewPalette() {
    const colors = [...new Set(this.colorsTarget.value.trim().split(/[\s,;]+/).filter(token => /^#?(?:[0-9a-f]{3}|[0-9a-f]{6})$/i.test(token)).map(token => {
      let hex = token.replace(/^#/, "").toUpperCase()
      if (hex.length === 3) hex = [...hex].map(char => char + char).join("")
      return `#${hex}`
    }))].slice(0, 5)
    const swatches = (colors.length ? colors : Array(4).fill(null)).map(color => {
      const swatch = document.createElement("span")
      if (color) {
        swatch.style.backgroundColor = color
        swatch.title = color
        swatch.setAttribute("aria-label", color)
      } else {
        swatch.className = "is-empty"
        swatch.setAttribute("aria-hidden", "true")
      }
      return swatch
    })
    this.swatchesTarget.replaceChildren(...swatches)
    this.colorCountTarget.textContent = colors.length ? `${colors.length} ${colors.length === 1 ? "cor" : "cores"}` : "1 a 5 cores"
  }

  async generate() {
    if (this.busy) return
    this.errorTarget.hidden = true
    this.statusTarget.textContent = ""
    const tokens = this.colorsTarget.value.trim().split(/[\s,;]+/)
    if (!tokens.length || tokens.some(token => !/^#?(?:[0-9a-f]{3}|[0-9a-f]{6})$/i.test(token))) {
      return this.showError("Informe de 1 a 5 cores HEX válidas, como #522D60.")
    }
    const colors = [...new Set(tokens.map(token => {
      let hex = token.replace(/^#/, "").toUpperCase()
      if (hex.length === 3) hex = [...hex].map(char => char + char).join("")
      return `#${hex}`
    }))]
    if (colors.length > 5) return this.showError("Use no máximo 5 cores diferentes.")

    this.setBusy(true)
    this.statusTarget.textContent = "O Gemini está preparando seu tema…"
    const controller = new AbortController()
    this.abortController = controller
    const timeout = setTimeout(() => controller.abort(), 35000)
    let generated = false
    try {
      const response = await fetch(this.urlValue, {
        method: "POST", credentials: "same-origin", cache: "no-store", signal: controller.signal,
        headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body: JSON.stringify({ colors: colors.join(" ") })
      })
      if (response.redirected || response.status === 401) throw new Error("Sua sessão expirou. Entre novamente no aplicativo.")
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Não foi possível gerar o tema agora.")
      if (!data.theme || typeof data.theme !== "object") throw new Error("A IA não retornou um tema válido. Tente novamente.")
      if (!this.alive || controller.signal.aborted) return
      this.formTarget.dispatchEvent(new CustomEvent("color-theme:generated", { bubbles: true, detail: { theme: data.theme } }))
      generated = true
      this.feedbackTarget.textContent = "Sugestão gerada. Confira as prévias e salve seu tema."
      this.feedbackTarget.hidden = false
    } catch (error) {
      if (this.alive && this.abortController === controller) this.showError(error.name === "AbortError" ? "A geração demorou para responder. Tente novamente." : error.message)
    } finally {
      clearTimeout(timeout)
      if (this.alive && this.abortController === controller) {
        this.setBusy(false)
        this.abortController = null
        if (generated) {
          this.hideDialog()
          this.formTarget.querySelector('[name="color_theme[name]"]').focus({ preventScroll: true })
        }
      }
    }
  }

  setBusy(busy) {
    this.busy = busy
    if (busy) {
      this.previousControls = [...this.formTarget.querySelectorAll("input, textarea, select, button, fieldset"), this.colorsTarget, this.buttonTarget].map(control => [control, control.disabled])
      this.previousControls.forEach(([control]) => { control.disabled = true })
    } else {
      this.previousControls?.forEach(([control, disabled]) => { control.disabled = disabled })
      this.previousControls = null
    }
    this.dialogTarget.setAttribute("aria-busy", String(busy))
    this.buttonLabelTarget.textContent = busy ? "Gerando…" : "Gerar tema"
    this.iconTarget.className = busy ? "spinner-border spinner-border-sm" : "bi bi-stars"
  }

  showError(message) {
    this.statusTarget.textContent = ""
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }
}
