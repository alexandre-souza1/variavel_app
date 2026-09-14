import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["itemsContainer", "itemTemplate"]
  static values = { actionPlanId: Number, bucketId: Number, taskId: Number }

  addItem() {
    const url = `/action_plans/${this.actionPlanIdValue}/buckets/${this.bucketIdValue}/tasks/${this.taskIdValue}/tasklist_items`

    fetch(url, {
      method: "POST",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      }
    })
    .then(response => {
      if (!response.ok) throw new Error("Falha ao criar item")
      return response.text()
    })
    .then(html => {
      Turbo.renderStreamMessage(html)
    })
    .catch(error => {
      console.error("Erro ao adicionar item:", error)
      // Fallback
      this.addLocalItem()
    })
  }

  addLocalItem(content = '') {
    this.localItemIndex = (this.localItemIndex || 0) + 1
    const index = Date.now() + this.localItemIndex
    const template = this.itemTemplateTarget.content.cloneNode(true)
    const newItem = template.querySelector('.task-checklist-item')
    newItem.innerHTML = newItem.innerHTML.replace(/NEW_RECORD/g, index)
    newItem.querySelector('.task-checklist-item__input').value = content
    this.itemsContainerTarget.appendChild(newItem)
  }

  pasteItems(event) {
    const input = event.target.closest('.task-checklist-item__input')
    const firstInput = this.itemsContainerTarget.querySelector('.task-checklist-item__input')

    if (!input || input !== firstInput) return

    const pastedText = event.clipboardData?.getData('text/plain') || ''
    const values = pastedText
      .split(/\r?\n/)
      .flatMap(row => row.split('\t'))
      .map(value => value.trim())
      .filter(Boolean)

    if (values.length <= 1) return

    event.preventDefault()
    input.value = values.shift()

    values.forEach(value => this.addLocalItem(value))

    // Dispara o autosave depois que todas as linhas já fazem parte do formulário.
    input.dispatchEvent(new Event('change', { bubbles: true }))
  }

  removeItem(event) {
    const item = event.target.closest(".task-checklist-item")
    if (!item) return

    const destroyField = item.querySelector('input[name$="[_destroy]"]')

    if (destroyField) {
      destroyField.value = "1"
      item.classList.add("d-none")
      // 🔥 Dispara o change para acionar o autosave
      destroyField.dispatchEvent(new Event("change", { bubbles: true }))
    } else {
      item.remove()
    }
  }

  clearAllItems(event) {
    if (confirm("Limpar todos os itens?")) {
      this.itemsContainerTarget.querySelectorAll('.task-checklist-item').forEach(item => {
        const destroyField = item.querySelector('input[name$="[_destroy]"]')
        if (destroyField) {
          destroyField.value = "1"
          item.classList.add("d-none")
          // 🔥 Dispara o change para acionar o autosave
          destroyField.dispatchEvent(new Event("change", { bubbles: true }))
        } else {
          item.remove()
        }
      })
    }
  }
}
