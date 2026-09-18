import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "colorSelect", "preview"]

  connect() {
    this.syncButtons()
    this.element.querySelectorAll("select[data-icon-map]").forEach((select) => {
      this.setSelectionIcon({ target: select })
    })
    const colorTheme = document.documentElement.dataset.colorTheme || "blue_teal"
    this.syncColorSelectors(colorTheme)
    this.syncColorPreview(colorTheme)
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
  }

  syncColorPreview(colorTheme) {
    const palettes = {
      blue_teal: ["#3368A0", "#66A3BF", "#C8DFDB", "#F2EFE7"],
      sage_teal: ["#2D9596", "#9AD0C2", "#265073", "#ECF4D6"],
      retro_orange: ["#527853", "#F7B787", "#EE7214", "#F9E8D9"],
      black_mint: ["#092328", "#12544F", "#2A835F", "#8BBB92"],
      white_tea_sage: ["#8B9A6E", "#F7F2EB", "#EAE2D6", "#EEEEEE"],
      earthy_forest_hues: ["#DAD7CD", "#A3B18A", "#588157", "#3A5A40", "#344E41"]
    }
    const colors = palettes[colorTheme] || palettes.blue_teal

    document.querySelectorAll('[data-theme-target="preview"]').forEach((preview) => {
      preview.querySelectorAll("[data-theme-preview-color]").forEach((swatch, index) => {
        swatch.style.backgroundColor = colors[index]
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
    const colors = {
      blue_teal: "#3368A0",
      sage_teal: "#265073",
      retro_orange: "#527853",
      black_mint: "#2A835F",
      white_tea_sage: "#8B9A6E",
      earthy_forest_hues: "#588157"
    }
    const colorTheme = document.documentElement.dataset.colorTheme || "blue_teal"

    document
      .querySelector("meta[name='theme-color']")
      ?.setAttribute("content", theme === "dark" ? "#0b0f0b" : colors[colorTheme])
  }
}
