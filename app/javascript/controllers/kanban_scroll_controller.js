import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["top", "spacer"]

  connect() {
    this.bottom = document.querySelector('[id^="kanban-"]')

    if (!this.bottom) return

    this.isSyncing = false

    this.topTarget.addEventListener("scroll", this.syncTop)
    this.bottom.addEventListener("scroll", this.syncBottom)

    this.syncWidth()

    window.addEventListener("resize", this.syncWidth)
  }

  disconnect() {
    this.topTarget.removeEventListener("scroll", this.syncTop)
    this.bottom?.removeEventListener("scroll", this.syncBottom)

    window.removeEventListener("resize", this.syncWidth)
  }

  syncTop = () => {
    if (this.isSyncing) return
    this.isSyncing = true

    this.bottom.scrollLeft = this.topTarget.scrollLeft

    this.isSyncing = false
  }

  syncBottom = () => {
    if (this.isSyncing) return
    this.isSyncing = true

    this.topTarget.scrollLeft = this.bottom.scrollLeft

    this.isSyncing = false
  }

  syncWidth = () => {
    if (!this.bottom || !this.hasSpacerTarget) return

    this.spacerTarget.style.width =
      this.bottom.scrollWidth + "px"
  }
}
