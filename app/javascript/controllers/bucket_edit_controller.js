import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["title"]

  edit(event) {
    event.stopPropagation()
    if (this.editing) return

    this.editing = true
    this.originalValue = this.titleTarget.textContent.trim()
    this.titleTarget.contentEditable = "true"
    this.titleTarget.classList.add("is-editing")
    this.titleTarget.focus()

    const selection = window.getSelection()
    const range = document.createRange()
    range.selectNodeContents(this.titleTarget)
    selection.removeAllRanges()
    selection.addRange(range)
  }

  async save() {
    if (!this.editing) return

    const value = this.titleTarget.textContent.trim()
    if (!value) {
      this.titleTarget.textContent = this.originalValue
      this.finish()
      return
    }

    const bucketId = this.element.dataset.bucketId
    const actionPlanId = this.element.dataset.actionPlanId

    const response = await fetch(`/action_plans/${actionPlanId}/buckets/${bucketId}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content
      },
      body: JSON.stringify({
        bucket: { name: value }
      })
    })

    if (!response.ok) this.titleTarget.textContent = this.originalValue
    this.finish()
  }

  enter(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.titleTarget.blur()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.titleTarget.textContent = this.originalValue
      this.finish()
    }
  }

  finish() {
    this.editing = false
    this.titleTarget.contentEditable = "false"
    this.titleTarget.classList.remove("is-editing")
  }
}
