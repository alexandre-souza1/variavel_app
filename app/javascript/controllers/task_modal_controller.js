import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"
import { renderStreamMessage } from "@hotwired/turbo"

export default class extends Controller {
  async open() {
    const taskId = this.element.dataset.taskId
    const planId = this.element.dataset.planId
    const bucketId = this.element.dataset.bucketId

    const response = await fetch(
      `/action_plans/${planId}/buckets/${bucketId}/tasks/${taskId}`
    )

    const html = await response.text()

    const container = document.getElementById("modal-container")

    container.innerHTML = html

    // força o Turbo a inicializar elementos novos
    Turbo.session.connectStreamSource(container)

    const modalElement = document.getElementById("taskModal")
    const modal = new bootstrap.Modal(modalElement)

    modalElement.addEventListener("hide.bs.modal", () => {
      if (document.activeElement) document.activeElement.blur()
    }, { once: true })

    modal.show()
  }
}
