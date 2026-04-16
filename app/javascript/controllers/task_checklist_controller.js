import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["itemsContainer", "itemTemplate"]

  addItem() {
    const index = Date.now()
    const template = this.itemTemplateTarget.content.cloneNode(true)
    const newItem = template.querySelector('.task-checklist-item')
    newItem.innerHTML = newItem.innerHTML.replace(/NEW_RECORD/g, index)
    this.itemsContainerTarget.appendChild(newItem)
  }

  removeItem(event) {
    const item = event.target.closest('.task-checklist-item')
    if (item) {
      const destroyField = item.querySelector('input[name$="[_destroy]"]')
      if (destroyField) {
        destroyField.value = "1"
        item.classList.add('d-none')
      } else {
        item.remove()
      }
    }
  }

  clearAllItems() {
    this.itemsContainerTarget.querySelectorAll('.task-checklist-item').forEach(item => {
      const destroyField = item.querySelector('input[name$="[_destroy]"]')
      if (destroyField) {
        destroyField.value = "1"
        item.classList.add('d-none')
      } else {
        item.remove()
      }
    })
  }
}
