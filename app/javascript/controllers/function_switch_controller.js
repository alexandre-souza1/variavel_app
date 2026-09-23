import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  change(event) {
    const link = event.currentTarget
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || link.classList.contains("is-active")) return

    event.preventDefault()
    if (this.element.classList.contains("is-changing")) return

    this.element.classList.add("is-changing")
    this.element.querySelector(".is-active")?.classList.remove("is-active")
    link.classList.add("is-active")
    document.querySelector(".consultas-report-page")?.classList.add("is-filtering")

    window.setTimeout(() => window.location.assign(link.href), 220)
  }
}
