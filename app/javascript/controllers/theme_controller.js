import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "colorSelect", "preview", "promotion"]

  connect() {
    this.colorThemes = JSON.parse(document.body.dataset.colorThemes || "{}")
    this.syncButtons()
    this.element.querySelectorAll("select[data-icon-map]").forEach((select) => {
      this.setSelectionIcon({ target: select })
    })
    const colorTheme = document.documentElement.dataset.colorTheme || "blue_teal"
    this.syncColorSelectors(colorTheme)
    this.syncColorPreview(colorTheme)
    if (this.hasPromotionTarget) {
      this.promotionTimer = window.setInterval(() => this.syncPromotions(), 60000)
    }
  }

  disconnect() {
    window.clearInterval(this.promotionTimer)
  }

  set(event) {
    const theme = event.params.value

    localStorage.setItem("theme", theme)
    document.documentElement.dataset.bsTheme = theme
    this.updateBrowserColor(theme)
    document.dispatchEvent(new CustomEvent("app:theme-changed"))
    this.syncButtons()
  }

  setColor(event) {
    const colorTheme = event.params?.color || event.currentTarget.value
    if (!this.colorThemes[colorTheme]) return
    const userId = document.body.dataset.userId || "guest"

    localStorage.setItem(`colorTheme:${userId}`, colorTheme)
    document.documentElement.dataset.colorTheme = colorTheme
    this.syncColorSelectors(colorTheme)
    this.updateBrowserColor(document.documentElement.dataset.bsTheme || "light")
    this.syncColorPreview(colorTheme)
    document.dispatchEvent(new CustomEvent("app:theme-changed"))
  }

  syncColorSelectors(colorTheme) {
    document.querySelectorAll('[data-theme-target="colorSelect"]').forEach((select) => {
      if (select.type === "radio") {
        select.checked = select.value === colorTheme
      } else {
        select.value = colorTheme
      }
    })
    this.syncPromotions(colorTheme)
  }

  syncPromotions(colorTheme = document.documentElement.dataset.colorTheme) {
    const today = new Intl.DateTimeFormat("sv-SE", {
      timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit", day: "2-digit"
    }).format(new Date())

    document.querySelectorAll('[data-theme-target="promotion"]').forEach((promotion) => {
      promotion.hidden = promotion.dataset.themeColorParam === colorTheme ||
        today < promotion.dataset.promotionStartsOn || today > promotion.dataset.promotionEndsOn
    })
  }

  syncColorPreview(colorTheme) {
    const colors = (this.colorThemes[colorTheme] || this.colorThemes.blue_teal)?.colors || []

    document.querySelectorAll('[data-theme-target="preview"]').forEach((preview) => {
      preview.querySelectorAll("[data-theme-preview-color]").forEach((swatch, index) => {
        swatch.style.backgroundColor = colors[index] || colors[0]
      })
    })
  }

  setSelectionIcon(event) {
    const icon = event.target.closest(".user-editor-select-group")?.querySelector(".user-editor-select-icon")
    const iconClass = JSON.parse(event.target.dataset.iconMap || "{}")[event.target.value] || "bi-building"

    if (!icon) return

    icon.className = `bi ${iconClass} user-editor-select-icon`
  }

  syncButtons() {
    const currentTheme = document.documentElement.dataset.bsTheme || "light"

    this.buttonTargets.forEach((button) => {
      const selected = button.dataset.themeValueParam === currentTheme

      button.classList.toggle("active", selected)
      button.setAttribute("aria-pressed", selected.toString())
    })
  }

  updateBrowserColor(theme) {
    const colorTheme = document.documentElement.dataset.colorTheme || "blue_teal"
    const palette = this.colorThemes[colorTheme] || this.colorThemes.blue_teal

    document
      .querySelector("meta[name='theme-color']")
      ?.setAttribute("content", palette?.[theme === "dark" ? "dark" : "light"] || "#3368A0")
  }
}
