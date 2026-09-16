import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.isDown = false
    this.isDragging = false
    this.pointerId = null
    this.startX = 0
    this.elementLeft = 0
    this.scrollLeft = 0
    this.pendingPageX = null
    this.hasMovedEnough = false
    this.velocity = 0
    this.lastX = 0
    this.lastTime = 0
    this.raf = null
    this.moveRaf = null
    this.suppressClickUntil = 0

    this.pointerDown = this.pointerDown.bind(this)
    this.pointerMove = this.pointerMove.bind(this)
    this.pointerUp = this.pointerUp.bind(this)
    this.suppressClick = this.suppressClick.bind(this)

    this.element.addEventListener("pointerdown", this.pointerDown)
    this.element.addEventListener("pointermove", this.pointerMove, { passive: false })
    this.element.addEventListener("pointerup", this.pointerUp)
    this.element.addEventListener("pointercancel", this.pointerUp)
    this.element.addEventListener("lostpointercapture", this.pointerUp)
    this.element.addEventListener("click", this.suppressClick, true)
  }

  disconnect() {
    this.element.removeEventListener("pointerdown", this.pointerDown)
    this.element.removeEventListener("pointermove", this.pointerMove)
    this.element.removeEventListener("pointerup", this.pointerUp)
    this.element.removeEventListener("pointercancel", this.pointerUp)
    this.element.removeEventListener("lostpointercapture", this.pointerUp)
    this.element.removeEventListener("click", this.suppressClick, true)
    cancelAnimationFrame(this.raf)
    cancelAnimationFrame(this.moveRaf)
  }

  pointerDown(event) {
    if (event.target.closest(".task-card, .drag-handle, [data-controller~='sortable']")) return
    // Tom Select renders options as divs; capturing their pointer redirects
    // the selection click to the board instead of the option.
    if (event.target.closest("form, label, .ts-wrapper, .ts-dropdown")) return
    if (event.target.closest("input, textarea, select, button, a, .btn, .dropdown, .accordion-button, .action-plan-kanban-done-toggle, .action-plan-kanban-card__title, [data-bucket-edit-target='input']")) return

    this.isDown = true
    this.pointerId = event.pointerId
    this.isDragging = false
    this.hasMovedEnough = false
    this.pendingPageX = null
    this.elementLeft = this.element.getBoundingClientRect().left
    this.startX = event.pageX - this.elementLeft
    this.scrollLeft = this.element.scrollLeft
    this.lastX = event.pageX
    this.lastTime = performance.now()
    this.velocity = 0

    cancelAnimationFrame(this.raf)
    this.element.classList.add("dragging")
    this.element.setPointerCapture?.(event.pointerId)
  }

  pointerMove(event) {
    if (!this.isDown || event.pointerId !== this.pointerId) return

    this.pendingPageX = event.pageX
    const walk = (event.pageX - this.elementLeft - this.startX) * 1.1

    if (Math.abs(walk) > 3) {
      this.hasMovedEnough = true
      window.getSelection()?.removeAllRanges()
      if (event.cancelable) event.preventDefault()
    }

    if (this.moveRaf) return

    this.moveRaf = requestAnimationFrame(() => {
      this.moveRaf = null
      if (!this.isDown || !this.hasMovedEnough || this.pendingPageX === null) return

      const currentWalk = (this.pendingPageX - this.elementLeft - this.startX) * 1.1
      this.element.scrollLeft = this.scrollLeft - currentWalk
      this.isDragging = true

      const now = performance.now()
      this.velocity = (this.pendingPageX - this.lastX) / (now - this.lastTime || 1)
      this.lastX = this.pendingPageX
      this.lastTime = now
    })

    if (this.hasMovedEnough && event.cancelable) event.preventDefault()
  }

  pointerUp(event) {
    if (!this.isDown || (event.pointerId !== undefined && event.pointerId !== this.pointerId)) return

    this.isDown = false
    this.pointerId = null
    this.pendingPageX = null
    cancelAnimationFrame(this.moveRaf)
    this.moveRaf = null
    this.element.classList.remove("dragging")

    if (event.pointerId !== undefined && this.element.hasPointerCapture?.(event.pointerId)) {
      this.element.releasePointerCapture(event.pointerId)
    }

    if (this.isDragging) {
      this.suppressClickUntil = performance.now() + 350
      this.startMomentum()
    }
  }

  suppressClick(event) {
    if (performance.now() >= this.suppressClickUntil) return

    event.preventDefault()
    event.stopPropagation()
    this.suppressClickUntil = 0
  }

  startMomentum() {
    let velocity = this.velocity * 18
    const step = () => {
      this.element.scrollLeft -= velocity
      velocity *= 0.94
      if (Math.abs(velocity) > 0.2) this.raf = requestAnimationFrame(step)
    }
    this.raf = requestAnimationFrame(step)
  }
}
