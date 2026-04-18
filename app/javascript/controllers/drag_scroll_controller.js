import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.isDown = false
    this.isDragging = false
    this.startX = 0
    this.scrollLeft = 0
    this.velocity = 0
    this.lastX = 0
    this.lastTime = 0
    this.raf = null

    // Bind
    this.mouseDown = this.mouseDown.bind(this)
    this.mouseMove = this.mouseMove.bind(this)
    this.mouseUp = this.mouseUp.bind(this)

    this.element.addEventListener("mousedown", this.mouseDown)
    this.element.addEventListener("mousemove", this.mouseMove)
    this.element.addEventListener("mouseup", this.mouseUp)
    this.element.addEventListener("mouseleave", this.mouseUp)

    // Mobile
    this.element.addEventListener("touchstart", this.mouseDown, { passive: true })
    this.element.addEventListener("touchmove", this.mouseMove, { passive: false })
    this.element.addEventListener("touchend", this.mouseUp)
  }

  // =============================
  // START
  // =============================
  mouseDown(e) {
    // ignora clique em elementos interativos
    if (e.target.closest("input, textarea, select, button, a, .task-card")) return

    this.isDown = true
    this.isDragging = false

    const pageX = e.touches ? e.touches[0].pageX : e.pageX

    this.startX = pageX - this.element.offsetLeft
    this.scrollLeft = this.element.scrollLeft

    this.lastX = pageX
    this.lastTime = Date.now()
    this.velocity = 0

    cancelAnimationFrame(this.raf)

    this.element.classList.add("dragging")
  }

  // =============================
  // MOVE
  // =============================
  mouseMove(e) {
    if (!this.isDown) return

    e.preventDefault()

    const pageX = e.touches ? e.touches[0].pageX : e.pageX
    const x = pageX - this.element.offsetLeft

    const walk = (x - this.startX) * 1.2
    this.element.scrollLeft = this.scrollLeft - walk

    // detectar drag real
    if (Math.abs(walk) > 5) {
      this.isDragging = true
    }

    // calcular velocidade
    const now = Date.now()
    const dx = pageX - this.lastX
    const dt = now - this.lastTime

    this.velocity = dx / (dt || 1)

    this.lastX = pageX
    this.lastTime = now
  }

  // =============================
  // END
  // =============================
  mouseUp() {
    if (!this.isDown) return

    this.isDown = false
    this.element.classList.remove("dragging")

    if (this.isDragging) {
      this.startMomentum()
    }
  }

  // =============================
  // MOMENTUM (inércia)
  // =============================
  startMomentum() {
    let velocity = this.velocity * 20 // força inicial

    const step = () => {
      this.element.scrollLeft -= velocity
      velocity *= 0.95 // atrito

      if (Math.abs(velocity) > 0.5) {
        this.raf = requestAnimationFrame(step)
      }
    }

    this.raf = requestAnimationFrame(step)
  }
}
