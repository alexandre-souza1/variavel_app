import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  submit(event) {
    // evita submit duplo com Enter
    if (event.type === "keydown" && event.key !== "Enter") return

    event.preventDefault()

    this.element.requestSubmit()
  }
}