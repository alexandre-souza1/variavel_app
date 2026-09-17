import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    nativeMobileTouch: { type: Boolean, default: false },
    handle: { type: String, default: "" }
  }

  connect() {
    console.log("[routines-drag-scroll] connect", this.element)

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

    this.mouseDown = this.mouseDown.bind(this)
    this.mouseMove = this.mouseMove.bind(this)
    this.mouseUp = this.mouseUp.bind(this)

    this.element.addEventListener("mousedown", this.mouseDown)
    this.element.addEventListener("mousemove", this.mouseMove, { passive: false })
    this.element.addEventListener("mouseup", this.mouseUp)
    this.element.addEventListener("mouseleave", this.mouseUp)
    this.element.addEventListener("touchstart", this.mouseDown, { passive: true })
    this.element.addEventListener("touchmove", this.mouseMove, { passive: false })
    this.element.addEventListener("touchend", this.mouseUp)
    this.element.addEventListener("touchcancel", this.mouseUp)
    window.addEventListener("mouseup", this.mouseUp)
    window.addEventListener("touchend", this.mouseUp)
    window.addEventListener("touchcancel", this.mouseUp)
  }

  disconnect() {
    console.log("[routines-drag-scroll] disconnect", this.element)

    this.element.removeEventListener("mousedown", this.mouseDown)
    this.element.removeEventListener("mousemove", this.mouseMove)
    this.element.removeEventListener("mouseup", this.mouseUp)
    this.element.removeEventListener("mouseleave", this.mouseUp)
    this.element.removeEventListener("touchstart", this.mouseDown)
    this.element.removeEventListener("touchmove", this.mouseMove)
    this.element.removeEventListener("touchend", this.mouseUp)
    this.element.removeEventListener("touchcancel", this.mouseUp)
    window.removeEventListener("mouseup", this.mouseUp)
    window.removeEventListener("touchend", this.mouseUp)
    window.removeEventListener("touchcancel", this.mouseUp)
    cancelAnimationFrame(this.raf)
    cancelAnimationFrame(this.moveRaf)
  }

  mouseDown(event) {
    // Let the browser handle both scroll axes on the mobile routine grid.
    if (event.touches && this.nativeMobileTouchValue && window.matchMedia("(max-width: 767.98px)").matches) return

    console.log("[routines-drag-scroll] mouseDown", {
      target: event.target,
      pageX: event.touches ? event.touches[0].pageX : event.pageX,
      handle: this.handleValue
    })

    if (event.target.closest("input, textarea, select, button, a, .routine-cell__input, .btn, .dropdown, .accordion-button")) {
      console.log("[routines-drag-scroll] mouseDown ignorado: alvo interativo")
      return
    }
    if (this.handleValue && !event.target.closest(this.handleValue)) {
      console.log("[routines-drag-scroll] mouseDown ignorado: fora do handle")
      return
    }

    this.isDown = true
    this.isDragging = false
    this.hasMovedEnough = false

    const pageX = event.touches ? event.touches[0].pageX : event.pageX
    this.elementLeft = this.element.getBoundingClientRect().left
    this.startX = pageX - this.elementLeft
    this.scrollLeft = this.element.scrollLeft
    this.lastX = pageX
    this.lastTime = performance.now()
    this.velocity = 0

    cancelAnimationFrame(this.raf)
    this.element.classList.add("dragging")

    console.log("[routines-drag-scroll] gesto iniciado", {
      startX: pageX,
      scrollLeft: this.scrollLeft
    })
  }

  mouseMove(event) {
    if (!this.isDown) return

    const pageX = event.touches ? event.touches[0].pageX : event.pageX
    this.pendingPageX = pageX

    if (this.moveRaf) return

    this.moveRaf = requestAnimationFrame(() => {
      this.moveRaf = null
      if (!this.isDown || this.pendingPageX === null) {
        return
      }

      const walk = (this.pendingPageX - this.elementLeft - this.startX) * 1.1
      if (Math.abs(walk) > 3) {
        this.hasMovedEnough = true
        window.getSelection()?.removeAllRanges()
      }
      if (!this.hasMovedEnough) return

      this.element.scrollLeft = this.scrollLeft - walk
      this.isDragging = true

      const now = performance.now()
      this.velocity = (this.pendingPageX - this.lastX) / (now - this.lastTime || 1)
      this.lastX = this.pendingPageX
      this.lastTime = now
    })

    if (this.hasMovedEnough && event.cancelable) event.preventDefault()
  }

  mouseUp() {
    console.log("[routines-drag-scroll] mouseUp", {
      isDown: this.isDown,
      isDragging: this.isDragging,
      hasMovedEnough: this.hasMovedEnough
    })

    if (!this.isDown) {
      console.log("[routines-drag-scroll] mouseUp ignorado: sem gesto ativo")
      return
    }

    this.isDown = false
    this.pendingPageX = null
    cancelAnimationFrame(this.moveRaf)
    this.moveRaf = null
    this.element.classList.remove("dragging")

    if (this.isDragging && !this.handleValue) {
      console.log("[routines-drag-scroll] iniciando momentum")
      this.startMomentum()
    } else {
      console.log("[routines-drag-scroll] momentum não iniciado", {
        isDragging: this.isDragging,
        handle: this.handleValue
      })
    }
  }

  startMomentum() {
    let velocity = this.velocity * 18
    console.log("[routines-drag-scroll] startMomentum", { velocity })

    const step = () => {
      this.element.scrollLeft -= velocity
      velocity *= 0.94
      if (Math.abs(velocity) > 0.2) {
        this.raf = requestAnimationFrame(step)
      } else {
        console.log("[routines-drag-scroll] momentum finalizado", {
          scrollLeft: this.element.scrollLeft
        })
      }
    }
    this.raf = requestAnimationFrame(step)
  }
}
