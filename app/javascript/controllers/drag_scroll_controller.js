import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    handle: { type: String, default: "" }
  }

  connect() {
    this.isDown = false
    this.isDragging = false
    this.startX = 0
    this.elementLeft = 0
    this.scrollLeft = 0
    this.velocity = 0
    this.lastX = 0
    this.lastTime = 0
    this.raf = null
    this.moveRaf = null
    this.pendingPageX = null
    this.hasMovedEnough = false
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

  pointerDown(e) {
    // Sortable owns task-card drags; the board scroller must stay idle.
    if (e.target.closest(".task-card, .drag-handle, [data-controller~='sortable']")) {
      console.log("[drag-scroll] ignorou pointerdown; alvo pertence ao sortable", e.target)
      return
    }

    const handleSelector = this.handleValue
    if (handleSelector) {
      const handleElement = e.target.closest(handleSelector)
      if (!handleElement) return
    }

    if (e.target.closest("input, textarea, select, button, a, .routine-cell__input, .btn, .dropdown, .accordion-button, .action-plan-kanban-done-toggle, .action-plan-kanban-card__title, [data-bucket-edit-target='input']")) {
      console.log("[drag-scroll] ignorou pointerdown; alvo interativo", e.target)
      return
    }

    this.isDown = true
    this.pointerId = e.pointerId
    this.isDragging = false
    this.hasMovedEnough = false

    const pageX = e.pageX

    this.elementLeft = this.element.getBoundingClientRect().left
    this.startX = pageX - this.elementLeft
    this.scrollLeft = this.element.scrollLeft

    this.lastX = pageX
    this.lastTime = performance.now()
    this.velocity = 0

    cancelAnimationFrame(this.raf)
    this.element.classList.add("dragging")

    this.element.setPointerCapture?.(e.pointerId)
    console.log("[drag-scroll] pointerdown", {
      pointerId: e.pointerId,
      target: e.target,
      startX: e.pageX,
      scrollLeft: this.scrollLeft
    })
  }

  pointerMove(e) {
    if (!this.isDown || e.pointerId !== this.pointerId) return

    const pageX = e.pageX
    const currentX = pageX - this.elementLeft
    const walk = (currentX - this.startX) * 1.1

    if (Math.abs(walk) > 3) {
      if (!this.hasMovedEnough) {
        console.log("[drag-scroll] iniciou arrasto", { walk, target: e.target })
      }
      this.hasMovedEnough = true
      window.getSelection()?.removeAllRanges()
      if (e.cancelable) e.preventDefault()
    }

    this.pendingPageX = pageX

    if (this.moveRaf) return

    this.moveRaf = requestAnimationFrame(() => {
      this.moveRaf = null
      if (!this.isDown || this.pendingPageX === null) return

      const currentPageX = this.pendingPageX
      if (!this.hasMovedEnough) return

      const x = currentPageX - this.elementLeft
      const currentWalk = (x - this.startX) * 1.1
      this.element.scrollLeft = this.scrollLeft - currentWalk
      this.isDragging = true

      const now = performance.now()
      const dx = currentPageX - this.lastX
      const dt = now - this.lastTime
      this.velocity = dx / (dt || 1)

      this.lastX = currentPageX
      this.lastTime = now
    })

    if (this.hasMovedEnough && e.cancelable) e.preventDefault()
  }

  pointerUp(e) {
    if (!this.isDown || (e.pointerId !== undefined && e.pointerId !== this.pointerId)) return

    console.log("[drag-scroll] pointerup", {
      pointerId: e.pointerId,
      isDragging: this.isDragging,
      hasMovedEnough: this.hasMovedEnough,
      scrollLeft: this.element.scrollLeft
    })

    this.isDown = false
    this.pointerId = null
    this.pendingPageX = null
    cancelAnimationFrame(this.moveRaf)
    this.moveRaf = null
    this.element.classList.remove("dragging")

    if (e.pointerId !== undefined && this.element.hasPointerCapture?.(e.pointerId)) {
      this.element.releasePointerCapture(e.pointerId)
    }

    if (this.isDragging && !this.handleValue) {
      this.suppressClickUntil = performance.now() + 350
      this.startMomentum()
    }
  }

  suppressClick(event) {
    if (performance.now() >= this.suppressClickUntil) return

    console.log("[drag-scroll] suprimiu click após arrasto", event.target)
    event.preventDefault()
    event.stopPropagation()
    this.suppressClickUntil = 0
  }

  startMomentum() {
    let velocity = this.velocity * 18

    const step = () => {
      this.element.scrollLeft -= velocity
      velocity *= 0.94

      if (Math.abs(velocity) > 0.2) {
        this.raf = requestAnimationFrame(step)
      }
    }

    this.raf = requestAnimationFrame(step)
  }
}
