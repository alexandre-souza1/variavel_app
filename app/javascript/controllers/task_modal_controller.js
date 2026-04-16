import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

export default class extends Controller {
  async open() {
    const taskId = this.element.dataset.taskId

    const response = await fetch(`/action_plans/${this.element.dataset.planId}/tasks/${taskId}`)
    const html = await response.text()

    document.getElementById("modal-container").innerHTML = html

    const modalElement = document.getElementById("taskModal")
    const modal = new bootstrap.Modal(modalElement)

    // 👇 AGORA NO MOMENTO CERTO
    modalElement.addEventListener("hide.bs.modal", () => {
      if (document.activeElement) {
        document.activeElement.blur()
      }
    }, { once: true })

    modal.show()
  }
}
