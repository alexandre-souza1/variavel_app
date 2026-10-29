import { Controller } from "@hotwired/stimulus"

const validHex = value => /^#[0-9a-f]{6}$/i.test(value)
const clamp = (value, min, max) => Math.min(max, Math.max(min, value))

export default class extends Controller {
  static targets = ["input", "trigger", "swatch", "panel", "plane", "thumb", "hue", "saturation", "brightness",
    "hueValue", "saturationValue", "brightnessValue", "hex", "valueSwatch", "suggestions", "error", "done"]

  connect() {
    this.syncFromInput()
    this.reposition = () => this.position()
    window.visualViewport?.addEventListener("resize", this.reposition)
    window.visualViewport?.addEventListener("scroll", this.reposition)
    // Capture also covers scrolling inside panels and other containers.
    document.addEventListener("scroll", this.reposition, true)
  }

  disconnect() {
    window.visualViewport?.removeEventListener("resize", this.reposition)
    window.visualViewport?.removeEventListener("scroll", this.reposition)
    document.removeEventListener("scroll", this.reposition, true)
  }

  syncFromInput() {
    if (this.updating) return
    const hex = validHex(this.inputTarget.value) ? this.inputTarget.value.toUpperCase() : "#FFFFFF"
    this.hsv = this.hexToHsv(hex)
    this.render()
  }

  toggle() {
    if (this.isOpen) return this.close()
    document.querySelectorAll(".color-picker-panel:popover-open").forEach(panel => panel.hidePopover())
    this.syncFromInput()
    this.buildSuggestions()
    this.render()
    this.panelTarget.showPopover()
    this.syncExpanded()
    this.position()
    this.hueTarget.focus({ preventScroll: true })
  }

  close(restoreFocus = true) {
    if (!this.isOpen) return
    this.panelTarget.hidePopover()
    this.syncExpanded()
    if (restoreFocus) this.triggerTarget.focus({ preventScroll: true })
  }

  outside(event) {
    if (this.isOpen && !event.composedPath().includes(this.element)) this.close(false)
  }

  escape(event) {
    if (!this.isOpen) return
    event.preventDefault()
    event.stopPropagation()
    this.close()
  }

  get isOpen() {
    return this.panelTarget.matches(":popover-open")
  }

  syncExpanded() {
    this.triggerTarget.setAttribute("aria-expanded", String(this.isOpen))
  }

  position() {
    if (!this.isOpen) return
    const viewport = window.visualViewport
    this.panelTarget.style.maxHeight = `${Math.max(0, (viewport?.height || window.innerHeight) - 24)}px`
    const leftEdge = (viewport?.offsetLeft || 0) + 12
    const topEdge = (viewport?.offsetTop || 0) + 12
    const rightEdge = leftEdge + (viewport?.width || window.innerWidth) - 24
    const bottomEdge = topEdge + (viewport?.height || window.innerHeight) - 24
    const trigger = this.triggerTarget.getBoundingClientRect()
    const panel = this.panelTarget.getBoundingClientRect()
    const below = trigger.bottom + 8
    const top = below + panel.height <= bottomEdge ? below : trigger.top - panel.height - 8
    this.panelTarget.style.left = `${clamp(trigger.left, leftEdge, Math.max(leftEdge, rightEdge - panel.width))}px`
    this.panelTarget.style.top = `${clamp(top, topEdge, Math.max(topEdge, bottomEdge - panel.height))}px`
  }

  startDrag(event) {
    if (event.button !== 0 || this.dragPointer != null) return
    event.preventDefault()
    this.dragPointer = event.pointerId
    this.planeTarget.setPointerCapture(event.pointerId)
    this.drag(event)
  }

  drag(event) {
    if (this.dragPointer !== event.pointerId) return
    const rect = this.planeTarget.getBoundingClientRect()
    this.hsv.s = clamp((event.clientX - rect.left) / rect.width, 0, 1) * 100
    this.hsv.v = (1 - clamp((event.clientY - rect.top) / rect.height, 0, 1)) * 100
    this.apply(this.hsvToHex(this.hsv))
  }

  endDrag(event) {
    if (this.dragPointer !== event.pointerId) return
    if (this.planeTarget.hasPointerCapture(event.pointerId)) this.planeTarget.releasePointerCapture(event.pointerId)
    this.dragPointer = null
  }

  adjust() {
    this.hsv = { h: Number(this.hueTarget.value), s: Number(this.saturationTarget.value), v: Number(this.brightnessTarget.value) }
    this.apply(this.hsvToHex(this.hsv))
  }

  editHex() {
    const value = this.hexTarget.value.trim()
    const valid = validHex(value)
    this.hexTarget.setAttribute("aria-invalid", String(!valid))
    this.errorTarget.hidden = valid
    this.doneTarget.disabled = !valid
    if (!valid) return
    this.hsv = this.hexToHsv(value)
    this.apply(value.toUpperCase())
  }

  choose(event) {
    const hex = event.params.value
    this.hsv = this.hexToHsv(hex)
    this.apply(hex)
  }

  apply(hex) {
    this.updating = true
    try {
      this.inputTarget.value = hex
      this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    } finally {
      this.updating = false
    }
    this.render(hex)
  }

  render(hex = validHex(this.inputTarget.value) ? this.inputTarget.value.toUpperCase() : "#FFFFFF") {
    const { h, s, v } = this.hsv
    this.swatchTarget.style.backgroundColor = hex
    this.valueSwatchTarget.style.backgroundColor = hex
    this.panelTarget.style.setProperty("--picker-hue-color", this.hsvToHex({ h, s: 100, v: 100 }))
    this.panelTarget.style.setProperty("--picker-full-color", this.hsvToHex({ h, s, v: 100 }))
    this.thumbTarget.style.left = `${s}%`
    this.thumbTarget.style.top = `${100 - v}%`
    this.hueTarget.value = h
    this.saturationTarget.value = s
    this.brightnessTarget.value = v
    this.hueValueTarget.value = `${Math.round(h)}°`
    this.saturationValueTarget.value = `${Math.round(s)}%`
    this.brightnessValueTarget.value = `${Math.round(v)}%`
    this.hexTarget.value = hex
    this.hexTarget.setAttribute("aria-invalid", "false")
    this.errorTarget.hidden = true
    this.doneTarget.disabled = false
    this.suggestionsTarget.querySelectorAll("button").forEach(button => {
      button.setAttribute("aria-pressed", String(button.dataset.colorPickerValueParam === hex))
    })
  }

  buildSuggestions() {
    const palette = [...this.element.closest("form").querySelectorAll('[data-color-theme-editor-target="color"]')]
      .map(input => input.value.toUpperCase()).filter(validHex)
    const colors = [...new Set([...palette, "#FFFFFF", "#1F2937", "#522D60", "#80426E", "#F2A67B", "#FFD38B", "#3368A0", "#2A835F"])].slice(0, 12)
    this.suggestionsTarget.replaceChildren(...colors.map(hex => {
      const button = document.createElement("button")
      button.type = "button"
      button.style.backgroundColor = hex
      button.setAttribute("aria-label", `Usar ${hex}`)
      button.dataset.action = "color-picker#choose"
      button.dataset.colorPickerValueParam = hex
      return button
    }))
  }

  hexToHsv(hex) {
    const [r, g, b] = hex.slice(1).match(/../g).map(channel => parseInt(channel, 16) / 255)
    const max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min
    let h = this.hsv?.h || 0
    if (delta) {
      if (max === r) h = ((g - b) / delta) % 6
      else if (max === g) h = (b - r) / delta + 2
      else h = (r - g) / delta + 4
      h = (h * 60 + 360) % 360
    }
    return { h, s: max ? delta / max * 100 : 0, v: max * 100 }
  }

  hsvToHex({ h, s, v }) {
    s /= 100
    v /= 100
    const channel = offset => {
      const k = (offset + h / 60) % 6
      return Math.round((v - v * s * Math.max(0, Math.min(k, 4 - k, 1))) * 255).toString(16).padStart(2, "0")
    }
    return `#${channel(5)}${channel(3)}${channel(1)}`.toUpperCase()
  }
}
