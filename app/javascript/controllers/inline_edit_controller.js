import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="inline-edit"
export default class extends Controller {
  static targets = ["display", "form"]

  edit(event) {
    event.preventDefault()

    this.displayTarget.classList.add("d-none")
    this.formTarget.classList.remove("d-none")

    this.formTarget.querySelector("input").focus()
  }
}
