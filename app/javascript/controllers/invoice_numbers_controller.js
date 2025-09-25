import { Controller } from "@hotwired/stimulus"

// Conecta com data-controller="invoice-numbers"
export default class extends Controller {
  static targets = ["container", "template"]

  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime())
    this.containerTarget.insertAdjacentHTML("beforeend", content)
  }

  remove(event) {
    event.preventDefault()
    let wrapper = event.target.closest(".nested-fields")
    if (wrapper.dataset.newRecord === "true") {
      wrapper.remove()
    } else {
      wrapper.querySelector("input[name*='_destroy']").value = 1
      wrapper.style.display = "none"
    }
  }
}
