import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "picker", "count", "search", "option", "checkbox", "empty"]

  connect() {
    this.mobileQuery = window.matchMedia("(max-width: 767px)")
    this.updateLayout = () => { this.panelTarget.open = !this.mobileQuery.matches }
    this.updateLayout()
    this.mobileQuery.addEventListener("change", this.updateLayout)
  }

  disconnect() { this.mobileQuery.removeEventListener("change", this.updateLayout) }

  updateCount() {
    const count = this.checkboxTargets.filter(input => input.checked).length
    this.countTarget.textContent = count ? `${count} selecionados` : "Todos os badges"
  }

  search() {
    const normalize = text => text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-BR")
    const query = normalize(this.searchTarget.value.trim())
    let visible = 0
    this.optionTargets.forEach(option => {
      option.hidden = !normalize(option.dataset.searchText).includes(query)
      if (!option.hidden) visible += 1
    })
    this.emptyTarget.hidden = visible > 0 || this.optionTargets.length === 0
  }

  preventSubmit(event) { event.preventDefault() }

  close() {
    if (!this.pickerTarget.open) return
    this.pickerTarget.open = false
    this.pickerTarget.querySelector("summary").focus()
  }

  closeOutside(event) {
    if (!this.pickerTarget.contains(event.target)) this.pickerTarget.open = false
  }
}
