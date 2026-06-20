import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.syncButtons()
  }

  set(event) {
    const theme = event.params.value

    localStorage.setItem("theme", theme)
    document.documentElement.dataset.bsTheme = theme
    this.updateBrowserColor(theme)
    this.syncButtons()
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
    document
      .querySelector("meta[name='theme-color']")
      ?.setAttribute("content", theme === "dark" ? "#111827" : "#3f8efc")
  }
}
