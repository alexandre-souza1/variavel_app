import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  open(event) {
    const dialog = document.getElementById(event.currentTarget.dataset.groupDialogId)
    if (!dialog || dialog.open) return
    this.reset()
    this.opener = event.currentTarget
    this.previousOverflow = document.body.style.overflow
    const root = document.documentElement
    this.previousGutter = root.style.scrollbarGutter
    if (window.innerWidth > root.clientWidth && !getComputedStyle(root).scrollbarGutter.includes("stable")) {
      root.style.scrollbarGutter = "stable"
    }
    this.activeDialog = dialog
    document.body.style.overflow = "hidden"
    dialog.showModal()
    dialog.querySelector('select[name="membership[group_code]"]')?.focus()
  }

  close(event) { event.currentTarget.closest("dialog").close() }

  dismiss(event) {
    if (event.target !== event.currentTarget) return
    const rect = event.currentTarget.getBoundingClientRect()
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) {
      event.currentTarget.close()
    }
  }

  closed(event) {
    if (event && event.currentTarget !== this.activeDialog) return
    const form = this.activeDialog?.querySelector("form")
    form?.reset()
    form?.querySelector("select")?.dispatchEvent(new Event("change", { bubbles: true }))
    document.body.style.overflow = this.previousOverflow || ""
    document.documentElement.style.scrollbarGutter = this.previousGutter || ""
    this.activeDialog = null
    if (this.opener?.isConnected) this.opener.focus({ preventScroll: true })
  }

  reset() {
    if (!this.activeDialog) return
    this.activeDialog.close()
    this.closed()
  }

  disconnect() { this.reset() }
}
