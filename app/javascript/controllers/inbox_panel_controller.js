import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]
  static values = { collapsed: Boolean }

  connect() {
    this.applyState(this.collapsedValue)
  }

  toggle() {
    const previous = this.collapsedValue
    const collapsed = !previous

    this.applyState(collapsed)

    fetch(this.element.dataset.inboxPanelPreferenceUrl, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify({ collapsed })
    }).then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
    }).catch(() => {
      this.applyState(previous)
    })
  }

  applyState(collapsed) {
    this.collapsedValue = collapsed
    this.element.classList.toggle("is-inbox-collapsed", collapsed)
    this.element.closest(".action-plan-with-inbox")?.classList.toggle("is-inbox-collapsed", collapsed)
    this.element.querySelector("[data-inbox-panel-toggle]")?.setAttribute("aria-expanded", String(!collapsed))
  }
}
