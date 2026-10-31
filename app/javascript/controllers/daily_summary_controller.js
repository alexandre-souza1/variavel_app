import { Controller } from "@hotwired/stimulus"
import { renderAssistantText } from "assistant_text"

export default class extends Controller {
  connect() {
    if (this.element.dataset.formatted === "true") return
    this.element.replaceChildren(renderAssistantText(this.element.textContent))
    this.element.dataset.formatted = "true"
  }
}
