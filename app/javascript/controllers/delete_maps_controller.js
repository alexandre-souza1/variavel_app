// app/javascript/controllers/delete_maps_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectAll", "mapaCheckbox", "deleteSelectedBtn", "counter"]

  connect() {
    this.updateCounters() // Inicializa
  }

  toggleAll(event) {
    const selectAllCheckbox = event.currentTarget
    const isChecked = selectAllCheckbox.checked
    const table = selectAllCheckbox.closest('table')
    if (!table) return

    const checkboxes = table.querySelectorAll('[data-delete-maps-target="mapaCheckbox"]')
    checkboxes.forEach(cb => cb.checked = isChecked)

    this.updateDeleteButton()
    this.updateCounters()
  }

  updateSelection(event) {
    this.updateDeleteButton()
    this.updateCounters()

    const checkbox = event.currentTarget
    const table = checkbox.closest('table')
    if (!table) return

    const selectAll = table.querySelector('[data-delete-maps-target="selectAll"]')
    if (selectAll) {
      const allCheckboxes = table.querySelectorAll('[data-delete-maps-target="mapaCheckbox"]')
      const allChecked = Array.from(allCheckboxes).every(cb => cb.checked)
      selectAll.checked = allChecked
    }
  }

  updateDeleteButton() {
    const anyChecked = this.mapaCheckboxTargets.some(cb => cb.checked)
    if (this.hasDeleteSelectedBtnTarget) {
      this.deleteSelectedBtnTarget.disabled = !anyChecked
    }
  }

  updateCounters() {
    this.counterTargets.forEach(counter => {
      const folder = counter.closest('.accordion-item')
      if (!folder) return

      const table = folder.querySelector('table')
      if (!table) return

      const checkboxes = table.querySelectorAll('[data-delete-maps-target="mapaCheckbox"]')
      const total = checkboxes.length
      const checked = Array.from(checkboxes).filter(cb => cb.checked).length

      // Atualiza o texto
      counter.textContent = `${checked} de ${total} selecionados`

      // Mostra/esconde a badge
      if (checked > 0) {
        counter.style.display = 'inline-block' // ou 'inline'
      } else {
        counter.style.display = 'none'
      }
    })
  }
}
