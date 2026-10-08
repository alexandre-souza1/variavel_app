import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { Turbo } from "@hotwired/turbo-rails"
import { updateOpenTaskCount } from "task_move_stream"

export default class extends Controller {
  static values = { bucketId: Number }

  connect() {
    console.log("[sortable] conectado", {
      element: this.element,
      source: this.element.dataset.sortableSource || "kanban"
    })
    this.sortable = Sortable.create(this.element, {
      group: {
        name: "action-plan-tasks",
        pull: true,
        put: true
      },
      animation: 150,
      delay: 250,
      delayOnTouchOnly: true,
      touchStartThreshold: 5,
      draggable: ".task-card",
      filter: "[data-task-move-pending]",
      preventOnFilter: false,
      forceFallback: true,
      fallbackOnBody: true,
      fallbackTolerance: 1,
      fallbackClass: "action-plan-sortable-fallback",
      onStart: (event) => {
        console.log("[sortable] iniciou arrasto", {
          item: event.item,
          from: event.from
        })
      },
      onEnd: this.onEnd.bind(this)
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  async onEnd(event) {
    console.log("[sortable] terminou arrasto", {
      item: event.item,
      from: event.from,
      to: event.to,
      oldIndex: event.oldIndex,
      newIndex: event.newIndex
    })
    const taskId =
      event.item.dataset.id ||
      event.item.querySelector("[data-id]")?.dataset.id

    const bucketElement = event.to.closest("[data-bucket-id]")
    const newBucketId = bucketElement.dataset.bucketId
    const oldBucketId = event.from.closest("[data-bucket-id]")?.dataset.bucketId
    const newPosition = event.newDraggableIndex
    const actionPlanId = this.element.closest("[data-action-plan-id]")?.dataset.actionPlanId
    if (oldBucketId === newBucketId && event.oldDraggableIndex === newPosition) return

    const oldPlanId = event.item.dataset.planId
    event.item.dataset.bucketId = newBucketId
    event.item.dataset.planId = event.to.dataset.sortableSource === "inbox" ? "" : actionPlanId || oldPlanId
    event.item.dataset.taskMovePending = "true"
    updateOpenTaskCount(oldBucketId)
    updateOpenTaskCount(newBucketId)
    const siblings = [...event.to.children].filter(element => element.matches(".task-card"))
    const nextCard = siblings[newPosition + 1]
    const previousCard = siblings[newPosition - 1]
    const context = new URLSearchParams(window.location.search)

    try {
      const response = await fetch(`/tasks/${taskId}/move`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
        },
        body: JSON.stringify({
          bucket_id: newBucketId,
          position: newPosition,
          following_task_id: nextCard?.dataset.taskId,
          preceding_task_id: previousCard?.dataset.taskId,
          action_plan_id: actionPlanId,
          view: context.get("view"),
          routine_id: context.get("routine_id")
        })
      })

      if (!response.ok) throw new Error("Não foi possível mover a tarefa")
      Turbo.renderStreamMessage(await response.text())
    } catch (error) {
      event.item.dataset.bucketId = oldBucketId
      event.item.dataset.planId = oldPlanId
      const siblings = [...event.from.children].filter(element => element.matches(".task-card") && element !== event.item)
      event.from.insertBefore(event.item, siblings[event.oldDraggableIndex] || null)
      updateOpenTaskCount(oldBucketId)
      updateOpenTaskCount(newBucketId)
      console.error(error)
    } finally {
      delete event.item.dataset.taskMovePending
    }
  }
}
