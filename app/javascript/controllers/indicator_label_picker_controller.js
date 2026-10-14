import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "option", "checkbox", "count", "clear", "empty"]

  connect() {
    if (this.hasCountTarget) this.updateCount()
  }

  updateCount() {
    const count = this.checkboxTargets.filter(input => input.checked).length
    this.countTarget.textContent = count === 0 ? "Nenhuma selecionada" : `${count} selecionada${count === 1 ? "" : "s"}`
    this.clearTarget.hidden = count === 0
  }

  filter() {
    const normalize = value => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-BR")
    const query = normalize(this.searchTarget.value.trim())
    this.optionTargets.forEach(option => { option.hidden = !normalize(option.dataset.labelName).includes(query) })
    this.emptyTarget.hidden = this.optionTargets.some(option => !option.hidden)
  }

  clear() {
    this.checkboxTargets.forEach(input => { input.checked = false })
    this.updateCount()
  }

  preventSubmit(event) { event.preventDefault() }
}
