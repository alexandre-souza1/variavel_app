import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

export default class extends Controller {

  connect() {
    this.pointerDown = false
    this.dragged = false
    this.startX = 0
    this.startY = 0

    this.handlePointerDown = this.handlePointerDown.bind(this)
    this.handlePointerMove = this.handlePointerMove.bind(this)
    this.handlePointerUp = this.handlePointerUp.bind(this)

    this.element.addEventListener("pointerdown", this.handlePointerDown)
    this.element.addEventListener("pointermove", this.handlePointerMove, { passive: true })
    this.element.addEventListener("pointerup", this.handlePointerUp)
    this.element.addEventListener("pointercancel", this.handlePointerUp)
  }

  disconnect() {
    this.element.removeEventListener("pointerdown", this.handlePointerDown)
    this.element.removeEventListener("pointermove", this.handlePointerMove)
    this.element.removeEventListener("pointerup", this.handlePointerUp)
    this.element.removeEventListener("pointercancel", this.handlePointerUp)
  }

  handlePointerDown(event) {
    console.log("[task-modal] pointerdown", {
      taskId: this.element.dataset.taskId,
      target: event.target
    })
    this.pointerDown = true
    this.dragged = false
    this.startX = event.clientX
    this.startY = event.clientY
  }

  handlePointerMove(event) {
    if (!this.pointerDown) return

    const movedX = Math.abs(event.clientX - this.startX)
    const movedY = Math.abs(event.clientY - this.startY)

    if ((movedX > 5 || movedY > 5) && !this.dragged) {
      this.dragged = true
      console.log("[task-modal] marcou gesto como arrasto", {
        taskId: this.element.dataset.taskId,
        movedX,
        movedY
      })
    }
  }

  handlePointerUp() {
    this.pointerDown = false
  }

  async open(event) {
    if (this.dragged) {
      console.log("[task-modal] bloqueou abertura após arrasto", this.element.dataset.taskId)
      event.preventDefault()
      event.stopPropagation()
      this.dragged = false
      return
    }

    console.log("[task-modal] abrindo modal", this.element.dataset.taskId)

    const taskId = this.element.dataset.taskId
    const planId = this.element.dataset.planId
    const bucketId = this.element.dataset.bucketId

    const response = await fetch(
      `/action_plans/${planId}/buckets/${bucketId}/tasks/${taskId}`
    )

    const html = await response.text()

    const container = document.getElementById("modal-container")

    container.innerHTML = html

    const modalElement = document.getElementById("taskModal")

    const modal = new bootstrap.Modal(modalElement)

    modalElement.addEventListener(
      "hide.bs.modal",
      () => {
        if (document.activeElement) {
          document.activeElement.blur()
        }
      },
      { once: true }
    )

    modal.show()
  }
}
