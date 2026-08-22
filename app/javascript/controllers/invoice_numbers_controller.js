import { Controller } from "@hotwired/stimulus"

// Conecta com data-controller="invoice-numbers"
export default class extends Controller {
  static targets = ["container", "template", "total"]

  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime())
    this.containerTarget.insertAdjacentHTML("beforeend", content)
    this.calculate()
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
    this.calculate()
  }

  calculate() {
    const total = [...this.containerTarget.querySelectorAll("input[name*='[amount]']")]
      .filter((input) => input.closest(".nested-fields")?.style.display !== "none")
      .reduce((sum, input) => sum + (parseFloat(input.value.replace(/\./g, "").replace(",", ".")) || 0), 0)
    const totalField = this.element.closest("form")?.querySelector("[data-invoice-numbers-target='total']")
    if (totalField) totalField.value = total.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
