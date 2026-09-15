import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "icon", "count"]

  connect() {
    this.loaded = false
  }

  toggle() {
    if (!this.hasListTarget) return

    const list = this.listTarget
    const opening = list.classList.contains("d-none")
    const bucketId = this.element.dataset.bucketId
    const kanban = document.querySelector("[id^='kanban-']")
    if (!kanban) return

    const actionPlanId = kanban.id.replace("kanban-", "")

    list.classList.toggle("d-none")

    if (this.hasIconTarget) {
      this.iconTarget.textContent = this.iconTarget.textContent === "▼" ? "▲" : "▼"
    }

    if (opening && !this.loaded) {
      this.load(bucketId, actionPlanId)
    }
  }

  async load(bucketId, actionPlanId) {
    const list = this.listTarget
    list.innerHTML = '<div class="action-plan-kanban-done-loading">Carregando...</div>'

    try {
      const response = await fetch(`/action_plans/${actionPlanId}/buckets/${bucketId}/done_tasks`)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      list.innerHTML = await response.text()
      this.loaded = true
    } catch (error) {
      console.error("Erro ao carregar tarefas concluídas:", error)
      list.innerHTML = '<div class="action-plan-kanban-done-loading">Erro ao carregar tarefas</div>'
    }
  }
}
