import { Controller } from "@hotwired/stimulus"

function compactName(value) {
  const label = String(this.getLabelForValue(value))
  const [name, registration] = label.split(" · ")
  const words = name.split(/\s+/)
  const shortName = words.length > 2 ? `${words[0]} ${words.at(-1)}` : name
  const text = registration ? `${shortName} · ${registration}` : shortName
  return text.length > 23 ? `${text.slice(0, 22)}…` : text
}

export default class extends Controller {
  static targets = ["title", "description", "dot"]
  static values = { chartId: String, slides: Array, compactLabels: Boolean }

  connect() {
    this.index = 0
    this.onChartLoad = this.updateChart.bind(this)
    window.addEventListener("chartkick:load", this.onChartLoad)
    this.syncControls()
    if (this.compactLabelsValue) this.updateChart()
  }

  disconnect() {
    window.removeEventListener("chartkick:load", this.onChartLoad)
    this.clearMotion()
  }

  select(event) {
    this.show(event.params.index)
  }

  previous() {
    this.show((this.index + this.slidesValue.length - 1) % this.slidesValue.length, true)
  }

  next() {
    this.show((this.index + 1) % this.slidesValue.length, true)
  }

  show(index, focus = false) {
    if (!this.slidesValue[index]) return

    this.index = index
    this.syncControls()
    this.transitionChart()
    if (focus) this.dotTargets[index].focus()
  }

  syncControls() {
    const slide = this.slidesValue[this.index]
    this.titleTarget.textContent = slide.title
    this.descriptionTarget.textContent = slide.description
    this.dotTargets.forEach((button, index) => {
      button.setAttribute("aria-pressed", String(index === this.index))
    })
  }

  clearMotion() {
    if (!this.motion) return
    this.motion.onfinish = null
    this.motion.cancel()
    this.motion = null
  }

  transitionChart() {
    this.clearMotion()
    const element = window.Chartkick?.charts[this.chartIdValue]?.getElement()
    if (!element || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.updateChart()
      return
    }

    this.motion = element.animate([
      { opacity: 1, transform: "translateY(0)" },
      { opacity: 0, transform: "translateY(4px)" }
    ], { duration: 90, fill: "forwards", easing: "ease-out" })
    this.motion.onfinish = () => {
      this.updateChart()
      this.clearMotion()
      this.motion = element.animate([
        { opacity: 0, transform: "translateY(6px)" },
        { opacity: 1, transform: "translateY(0)" }
      ], { duration: 180, easing: "cubic-bezier(.22, 1, .36, 1)" })
    }
  }

  updateChart() {
    const chart = window.Chartkick?.charts[this.chartIdValue]
    if (!chart) return

    const primary = getComputedStyle(document.documentElement).getPropertyValue("--app-primary").trim()
    const options = { ...chart.getOptions(), colors: [primary] }
    if (this.compactLabelsValue) {
      const library = options.library || {}
      const y = library.scales?.y || {}
      options.library = { ...library, scales: { ...library.scales, y: { ...y, ticks: { ...y.ticks, callback: compactName } } } }
    }
    chart.updateData(this.slidesValue[this.index].data, options)
  }
}
