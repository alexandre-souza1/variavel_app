import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["stage", "page", "dot", "status"]

  connect() {
    this.index = 0
    this.onChartLoad = this.resizeCharts.bind(this)
    window.addEventListener("chartkick:load", this.onChartLoad)
    this.syncPages()
  }

  disconnect() {
    window.removeEventListener("chartkick:load", this.onChartLoad)
    window.cancelAnimationFrame(this.resizeFrame)
    this.clearMotion()
  }

  select(event) {
    this.show(event.params.index)
  }

  previous() {
    this.show((this.index + this.pageTargets.length - 1) % this.pageTargets.length, true)
  }

  next() {
    this.show((this.index + 1) % this.pageTargets.length, true)
  }

  show(index, focus = false) {
    if (!this.pageTargets[index]) return

    const previousIndex = this.index
    const previousPage = this.pageTargets[previousIndex]
    this.clearMotion()
    this.index = index
    this.syncPages()
    this.resizeCharts()
    if (focus) this.dotTargets[index].focus()

    if (index === previousIndex || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const nextPage = this.pageTargets[index]
    const direction = index > previousIndex ? 1 : -1
    previousPage.hidden = false
    previousPage.classList.add("mapas-chart-page--leaving")
    const options = { duration: 260, easing: "cubic-bezier(.22, 1, .36, 1)" }
    const outgoing = previousPage.animate([
      { opacity: 1, transform: "translateX(0)" },
      { opacity: 0, transform: `translateX(${-direction * 28}px)` }
    ], options)
    const incoming = nextPage.animate([
      { opacity: 0, transform: `translateX(${direction * 28}px)` },
      { opacity: 1, transform: "translateX(0)" }
    ], options)
    this.motions = [outgoing, incoming]
    incoming.onfinish = () => {
      this.clearMotion()
      this.syncPages()
    }
  }

  syncPages() {
    this.pageTargets.forEach((page, index) => {
      page.hidden = index !== this.index
      page.inert = index !== this.index
      page.setAttribute("aria-hidden", String(index !== this.index))
    })
    this.dotTargets.forEach((dot, index) => dot.setAttribute("aria-pressed", String(index === this.index)))
    this.statusTarget.textContent = this.dotTargets[this.index].getAttribute("aria-label").replace("Mostrar ", "")
  }

  resizeCharts() {
    window.cancelAnimationFrame(this.resizeFrame)
    this.resizeFrame = window.requestAnimationFrame(() => {
      const page = this.pageTargets[this.index]
      Object.values(window.Chartkick?.charts || {}).forEach(wrapper => {
        if (!page.contains(wrapper.getElement())) return

        const chart = wrapper.getChartObject()
        chart?.resize()
      })
    })
  }

  clearMotion() {
    this.motions?.forEach(motion => { motion.onfinish = null; motion.cancel() })
    this.motions = []
    this.pageTargets.forEach(page => page.classList.remove("mapas-chart-page--leaving"))
  }

}
