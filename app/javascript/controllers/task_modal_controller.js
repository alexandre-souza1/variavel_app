import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async open() {
    const taskId = this.element.dataset.taskId

    const response = await fetch(`/action_plans/${this.element.dataset.planId}/tasks/${taskId}`)
    const html = await response.text()

    document.getElementById("modal-container").innerHTML = html

    const modal = new bootstrap.Modal(document.getElementById("taskModal"))
    modal.show()
  }
}
