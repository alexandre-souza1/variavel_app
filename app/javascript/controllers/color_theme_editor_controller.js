import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["color", "preview", "name", "decoration", "promotionToggle", "promotionFields", "promotionPanel"]
  static values = { darkPalette: Object, originalTheme: String, originalPalette: Array }

  connect() {
    this.refresh()
    this.togglePromotion()
  }

  togglePromotion() {
    const enabled = this.promotionToggleTarget.checked
    this.promotionPanelTarget.classList.toggle("is-open", enabled)
    this.promotionPanelTarget.inert = !enabled
    this.promotionFieldsTarget.disabled = !enabled
    this.promotionToggleTarget.setAttribute("aria-expanded", String(enabled))
    this.promotionFieldsTarget.querySelectorAll("[data-promotion-date]").forEach(input => {
      input.required = enabled
    })
  }

  applyGenerated(event) {
    const fields = ["name", "description", "decoration", "base_color", "primary_color", "accent_color", "highlight_color", "extra_color", "promotion_text"]
    const inputs = fields.map(field => {
      const input = this.element.querySelector(`[name="color_theme[${field}]"]`)
      if (input) input.value = event.detail.theme[field] || ""
      return input
    }).filter(Boolean)
    inputs.forEach(input => input.dispatchEvent(new Event("input", { bubbles: true })))
    this.refresh()
  }

  refresh() {
    this.colors ||= { base: "#522D60", primary: "#80426E", accent: "#F2A67B", highlight: "#FFD38B" }
    const extraColor = this.colorTargets.find(input => input.dataset.colorKey === "extra_color")?.value || ""
    this.colorTargets.forEach(input => {
      if (!/^#[0-9a-f]{6}$/i.test(input.value)) return
      this.colors[input.dataset.colorKey.replace("_color", "")] = input.value
    })
    if (!/^#[0-9a-f]{6}$/i.test(extraColor)) delete this.colors.extra
    this.previewTargets.forEach(preview => {
      const colors = { ...this.colors, ...this.previewColors(preview.dataset.previewMode) }
      Object.entries(colors).forEach(([name, value]) => preview.style.setProperty(`--preview-${name}`, value))
      preview.querySelector("[data-preview-extra]").hidden = !/^#[0-9a-f]{6}$/i.test(extraColor)
      preview.querySelector("[data-preview-name]").textContent = this.nameTarget.value || "Seu tema"
      preview.querySelector("[data-preview-decoration]").textContent = this.decorationTarget.value
    })
  }

  previewColors(mode) {
    const bar = this.readable(this.colors.base, "#FFFFFF", "#000000")
    const action = this.readable(this.colors.primary, "#FFFFFF", "#000000")
    if (mode === "dark") {
      if (this.originalThemeValue && Object.values(this.colors).map(color => color.toUpperCase()).join() === this.originalPaletteValue.join()) {
        return this.originalDarkColors ||= this.originalDarkPreview()
      }
      const surfaces = this.darkSurfaces()
      const backdrop = Object.values(surfaces).reduce((brightest, color) => this.luminance(color) > this.luminance(brightest) ? color : brightest)
      return { bar: surfaces.bar, action, background: surfaces.page,
        ink: this.readable(this.blend(this.colors.highlight, "#FFFFFF", .9), backdrop, "#FFFFFF"),
        muted: this.readable(this.blend(this.colors.highlight, "#FFFFFF", .55), backdrop, "#FFFFFF"),
        "accent-ink": this.readablePrimaryOnDark(backdrop) }
    }
    const background = this.blend(this.colors.highlight, "#FFFFFF", .93)
    return { bar, action, background, ink: this.readable(bar, background, "#000000"),
      muted: this.readable(this.blend(bar, "#FFFFFF", .2), background, "#000000"),
      "accent-ink": this.readable(action, background, "#000000") }
  }

  originalDarkPreview() {
    // Lê a paleta do CSS para manter a prévia fiel sem duplicar as cores no JS.
    const probe = document.createElement("div")
    probe.hidden = true
    probe.dataset.bsTheme = "dark"
    probe.dataset.colorTheme = this.originalThemeValue
    document.body.append(probe)
    try {
      const styles = getComputedStyle(probe)
      const tokens = { bar: "app-strong", action: "app-button-solid", background: "app-dark-page",
        ink: "app-dark-text", muted: "app-dark-muted", "accent-ink": "app-primary" }
      return Object.fromEntries(Object.entries(tokens).map(([name, token]) => [name, styles.getPropertyValue(`--${token}`).trim()]))
    } finally { probe.remove() }
  }

  darkSurfaces() {
    const recipe = this.darkPaletteValue
    const rgb = hex => hex.slice(1).match(/../g).map(channel => parseInt(channel, 16))
    const source = Object.values(this.colors).find(color => {
      const channels = rgb(color), max = Math.max(...channels)
      return max > 0 && (max - Math.min(...channels)) / max >= recipe.saturation_floor
    }) || this.colors.base
    const channels = rgb(source), max = Math.max(...channels)
    const tint = "#" + channels.map(channel => Math.round(max ? channel / max * recipe.tint_peak : recipe.tint_peak).toString(16).padStart(2, "0")).join("")
    const surfaces = Object.fromEntries(Object.entries(recipe.surfaces).map(([name, [neutral, amount]]) => [name, this.blend(neutral, tint, amount)]))
    surfaces.hover = this.blend(surfaces.elevated, tint, recipe.hover_mix)
    return surfaces
  }

  blend(color, other, amount) {
    const rgb = hex => hex.slice(1).match(/../g).map(channel => parseInt(channel, 16))
    return "#" + rgb(color).map((channel, i) => Math.round(channel * (1 - amount) + rgb(other)[i] * amount).toString(16).padStart(2, "0")).join("").toUpperCase()
  }

  readable(color, background, toward) {
    const backdrop = this.luminance(background)
    let candidate = color
    while (true) {
      const foreground = this.luminance(candidate)
      if ((Math.max(foreground, backdrop) + .05) / (Math.min(foreground, backdrop) + .05) >= 4.5) return candidate
      candidate = this.blend(candidate, toward, .1)
    }
  }

  readablePrimaryOnDark(background) {
    const channels = this.colors.primary.slice(1).match(/../g).map(channel => parseInt(channel, 16))
    const originalPeak = Math.max(...channels)
    let peak = originalPeak, candidate = this.colors.primary
    while (peak > 0 && peak < 255 && (this.luminance(candidate) + .05) / (this.luminance(background) + .05) < 4.5) {
      peak = Math.min(Math.ceil(peak * this.darkPaletteValue.primary_boost), 255)
      candidate = "#" + channels.map(channel => Math.round(channel / originalPeak * peak).toString(16).padStart(2, "0")).join("").toUpperCase()
    }
    return this.readable(candidate, background, "#FFFFFF")
  }

  luminance(hex) {
    return hex.slice(1).match(/../g).map(channel => {
      const value = parseInt(channel, 16) / 255
      return value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4
    }).reduce((total, channel, i) => total + channel * [.2126, .7152, .0722][i], 0)
  }
}
