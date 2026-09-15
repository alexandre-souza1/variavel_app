import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

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
      draggable: ".task-card",
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
    const crossedInbox = event.from.dataset.sortableSource === "inbox" ||
      event.to.dataset.sortableSource === "inbox"

    const newPosition = event.newIndex

    const response = await fetch(`/tasks/${taskId}/move`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content
      },
      body: JSON.stringify({
        bucket_id: newBucketId,
        position: newPosition
      })
    })

    if (!response.ok) {
      window.location.reload()
      return
    }

    if (oldBucketId !== newBucketId && crossedInbox) {
      event.item.dataset.bucketId = newBucketId
    }
  }
}
