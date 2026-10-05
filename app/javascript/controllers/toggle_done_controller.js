import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "icon", "count"]
  static values = { preloaded: Boolean }

  connect() {
    this.loaded = this.preloadedValue
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
      this.iconTarget.classList.toggle("is-expanded", opening)
    }
    this.element.querySelector(".action-plan-kanban-done-toggle")?.setAttribute("aria-expanded", String(opening))

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
