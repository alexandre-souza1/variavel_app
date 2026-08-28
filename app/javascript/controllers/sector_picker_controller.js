import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.closeWhenClickedOutside = this.closeWhenClickedOutside.bind(this)
    this.closeWithEscape = this.closeWithEscape.bind(this)

    document.addEventListener("click", this.closeWhenClickedOutside)
    document.addEventListener("keydown", this.closeWithEscape)
  }

  disconnect() {
    document.removeEventListener("click", this.closeWhenClickedOutside)
    document.removeEventListener("keydown", this.closeWithEscape)
  }

  closeWhenClickedOutside(event) {
    if (!this.element.contains(event.target)) {
      this.element.open = false
    }
  }

  closeWithEscape(event) {
    if (event.key === "Escape") {
      this.element.open = false
    }
  }
}
