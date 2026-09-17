import { Controller } from "@hotwired/stimulus"

// Navigation only: keep the original editable cells and their save lifecycle.
export default class extends Controller {
  static targets = ["viewport"]

  navigate(event) {
    const viewport = this.viewportTarget
    if (event.target.value === "") {
      viewport.scrollLeft = 0
      return
    }

    const day = viewport.querySelectorAll("thead .routine-day")[Number(event.target.value)]
    const label = viewport.querySelector("thead .col-indicator")
    if (!day || !label) return

    viewport.scrollLeft += day.getBoundingClientRect().left -
      viewport.getBoundingClientRect().left - label.getBoundingClientRect().width
  }
}
