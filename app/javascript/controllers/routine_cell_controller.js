import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static targets = [
    "display",
    "input"
  ]

  static values = {
    id: Number,
    value: String
  }

  edit() {

    this.inputTarget.value = this.valueValue || ""

    this.displayTarget.classList.add("d-none")

    this.inputTarget.classList.remove("d-none")

    this.inputTarget.focus()

    this.inputTarget.select()

  }

}
