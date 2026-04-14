import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "icon", "count"]

  connect() {
    this.loaded = false
  }

  toggle() {
    if (!this.hasListTarget) return

    const list = this.listTarget
    const bucketElement = this.element.closest("[data-bucket-id]")
    const bucketId = bucketElement.dataset.bucketId
    const kanban = document.querySelector("[id^='kanban-']")
    const actionPlanId = kanban.id.replace("kanban-", "")

    // Carrega só na primeira abertura
    if (!this.loaded) {
      this.load(bucketId, actionPlanId)
      this.loaded = true
    }

    list.classList.toggle("d-none")

    if (this.hasIconTarget) {
      this.iconTarget.textContent = this.iconTarget.textContent === "▼" ? "▲" : "▼"
    }
  }

  load(bucketId, actionPlanId) {
    const list = this.listTarget
    list.innerHTML = "Carregando..."

    fetch(`/action_plans/${actionPlanId}/buckets/${bucketId}/done_tasks`)
      .then(r => r.text())
      .then(html => list.innerHTML = html)
      .catch(error => {
        console.error("Erro ao carregar tarefas concluídas:", error)
        list.innerHTML = "Erro ao carregar tarefas"
      })
  }
}