import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["title", "input"]

  edit() {
    this.titleTarget.classList.add("d-none")
    this.inputTarget.classList.remove("d-none")
    this.inputTarget.focus()
  }

  async save() {
    const value = this.inputTarget.value
    const bucketId = this.element.dataset.bucketId

    await fetch(`/buckets/${bucketId}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content
      },
      body: JSON.stringify({
        bucket: { name: value }
      })
    })

    this.titleTarget.innerText = value

    this.inputTarget.classList.add("d-none")
    this.titleTarget.classList.remove("d-none")
  }

  enter(event) {
    if (event.key === "Enter") {
      this.save()
    }
  }
}