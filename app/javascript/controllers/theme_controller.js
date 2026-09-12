import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "colorSelect"]

  connect() {
    this.syncButtons()
    this.element.querySelectorAll("select[data-icon-map]").forEach((select) => {
      this.setSelectionIcon({ target: select })
    })
  }

  set(event) {
    const theme = event.params.value

    localStorage.setItem("theme", theme)
    document.documentElement.dataset.bsTheme = theme
    this.updateBrowserColor(theme)
    this.syncButtons()
  }

  setColor(event) {
    const colorTheme = event.target.value
    const userId = document.body.dataset.userId || "guest"

    localStorage.setItem(`colorTheme:${userId}`, colorTheme)
    document.documentElement.dataset.colorTheme = colorTheme
    this.updateBrowserColor(document.documentElement.dataset.bsTheme || "light")
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
