import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  reset(event) {
    if (event.detail.success) {
      this.element.reset()

      const textarea = this.element.querySelector("textarea")
      if (textarea) textarea.focus()
    }
  }
}