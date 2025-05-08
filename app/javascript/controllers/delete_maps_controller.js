import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectAll", "mapaCheckbox", "deleteSelectedBtn",
                   "monthSelect", "deleteByMonthBtn"]

  connect() {
    console.log("Delete Maps Controller connected!")
    this.updateDeleteButtonsState()
  }

  toggleAll() {
    const allChecked = this.selectAllTarget.checked
    this.mapaCheckboxTargets.forEach(checkbox => {
      checkbox.checked = allChecked
    })
    this.updateDeleteButtonsState()
  }

  updateSelection() {
    this.selectAllTarget.checked = this.allCheckboxesChecked()
    this.updateDeleteButtonsState()
  }

  updateMonthSelection() {
    const monthSelected = this.monthSelectTarget.value !== ""
    this.deleteByMonthBtnTarget.disabled = !monthSelected

    // Atualiza o parâmetro no formulário
    const form = this.deleteByMonthBtnTarget.form
    const baseUrl = form.action.split('?')[0]
    form.action = `${baseUrl}?month=${this.monthSelectTarget.value}`
  }

  allCheckboxesChecked() {
    return this.mapaCheckboxTargets.length > 0 &&
           this.mapaCheckboxTargets.every(checkbox => checkbox.checked)
  }

  updateDeleteButtonsState() {
    const anyChecked = this.mapaCheckboxTargets.some(checkbox => checkbox.checked)
    this.deleteSelectedBtnTarget.disabled = !anyChecked
  }
}
