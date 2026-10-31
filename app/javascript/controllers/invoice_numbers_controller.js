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
      const destroy = wrapper.querySelector("input[type='checkbox'][name*='_destroy']")
      if (destroy) destroy.checked = true
      wrapper.style.display = "none"
      wrapper.querySelectorAll("input:not([type='hidden']):not([type='checkbox']), select").forEach((field) => { field.disabled = true })
    }
    this.calculate()
  }

  selectZero(event) {
    const input = event.currentTarget
    if (/^0+(?:[.,]0+)?$/.test(input.value.trim())) input.select()
  }

  calculate() {
    const total = [...this.containerTarget.querySelectorAll("input[name*='[amount]']")]
      .filter((input) => input.closest(".nested-fields")?.style.display !== "none")
      .reduce((sum, input) => {
        const value = input.value.includes(",") ? input.value.replace(/\./g, "").replace(",", ".") : input.value
        return sum + (Number(value) || 0)
      }, 0)
    const totalField = this.element.closest("form")?.querySelector("[data-invoice-numbers-target='total']")
    if (totalField) totalField.value = total.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
