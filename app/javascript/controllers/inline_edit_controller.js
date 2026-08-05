import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "form"]

  connect() {
    this.originalValue = null
    this.clickOutside = this.clickOutside.bind(this)

    document.addEventListener("click", this.clickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutside)
  }

  edit(event) {
    event.preventDefault()
    event.stopPropagation()

    const input = this.formTarget.querySelector("input")

    this.originalValue = input.value

    this.displayTarget.classList.add("d-none")
    this.formTarget.classList.remove("d-none")

    input.focus()
  }

  clickOutside(event) {
    if (!this.formTarget.classList.contains("d-none") &&
        !this.element.contains(event.target)) {

      const input = this.formTarget.querySelector("input")

      if (input && input.value === this.originalValue) {
        this.close()
      }
    }
  }

  close() {
    this.formTarget.classList.add("d-none")
    this.displayTarget.classList.remove("d-none")
  }
}
