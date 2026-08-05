import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]

  toggle() {
    const content = this.contentTarget

    if (content.classList.contains("open")) {
      content.style.maxHeight = "0px"
      content.classList.remove("open")
    } else {
      content.classList.add("open")
      content.style.maxHeight = `${content.scrollHeight}px`

      content.querySelector("input, select")?.focus()
    }
  }
}
