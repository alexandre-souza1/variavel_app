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

  addLocalItem() {
    const index = Date.now()
    const template = this.itemTemplateTarget.content.cloneNode(true)
    const newItem = template.querySelector('.task-checklist-item')
    newItem.innerHTML = newItem.innerHTML.replace(/NEW_RECORD/g, index)
    this.itemsContainerTarget.appendChild(newItem)
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
