import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = { bucketId: Number }

  connect() {
    this.sortable = Sortable.create(this.element, {
      group: "tasks",
      animation: 150,
      onEnd: this.onEnd.bind(this)
    })
  }

  async onEnd(event) {
    const taskId = event.item.dataset.id
    const newBucketId = event.to.dataset.bucketId
    const newPosition = event.newIndex

    await fetch(`/tasks/${taskId}/move`, {
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
  }
}
