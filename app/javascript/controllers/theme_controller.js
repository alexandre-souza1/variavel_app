import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "colorSelect", "preview"]

  connect() {
    this.syncButtons()
    this.element.querySelectorAll("select[data-icon-map]").forEach((select) => {
      this.setSelectionIcon({ target: select })
    })
    this.syncColorPreview(document.documentElement.dataset.colorTheme || "blue_teal")
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
    const colorTheme = event.currentTarget.value
    const userId = document.body.dataset.userId || "guest"

    localStorage.setItem(`colorTheme:${userId}`, colorTheme)
    document.documentElement.dataset.colorTheme = colorTheme
    this.updateBrowserColor(document.documentElement.dataset.bsTheme || "light")
    this.syncColorPreview(colorTheme)
    document.dispatchEvent(new CustomEvent("app:theme-changed"))
  }

  syncColorPreview(colorTheme) {
    if (!this.hasPreviewTarget) return

    const palettes = {
      blue_teal: ["#3368A0", "#66A3BF", "#C8DFDB", "#F2EFE7"],
      sage_teal: ["#2D9596", "#9AD0C2", "#265073", "#ECF4D6"],
      retro_orange: ["#527853", "#F7B787", "#EE7214", "#F9E8D9"]
    }
    const colors = palettes[colorTheme] || palettes.blue_teal

    this.previewTarget.querySelectorAll("[data-theme-preview-color]").forEach((swatch, index) => {
      swatch.style.backgroundColor = colors[index]
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
    const colors = {
      blue_teal: "#3368A0",
      sage_teal: "#265073",
      retro_orange: "#527853"
    }
    const colorTheme = document.documentElement.dataset.colorTheme || "blue_teal"

    document
      .querySelector("meta[name='theme-color']")
      ?.setAttribute("content", theme === "dark" ? "#0b0f0b" : colors[colorTheme])
  }
}
