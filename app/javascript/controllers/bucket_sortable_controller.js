import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = {
    actionPlanId: Number
  }

  connect() {
    console.log("BucketSortableController connected")

    this.sortable = Sortable.create(this.element, {
      animation: 150,
      draggable: ".kanban-column",
      handle: ".drag-handle",

      onStart: () => console.log("START"),
      onEnd: () => {
        console.log("END")
        this.save()
      }
    })

    console.log(this.sortable)
  }

  save() {
    const ids = [...this.element.querySelectorAll("[data-bucket-id]")]
      .map(el => el.dataset.bucketId)

    fetch(`/action_plans/${this.actionPlanIdValue}/sort_buckets`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      },
      body: JSON.stringify({
        bucket_ids: ids
      })
    })
  }
}
