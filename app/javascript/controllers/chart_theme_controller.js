import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.refreshCharts = this.refreshCharts.bind(this)
    document.addEventListener("app:theme-changed", this.refreshCharts)

    // O Chartkick pode montar os gráficos logo depois do Stimulus.
    this.refreshTimer = window.setTimeout(this.refreshCharts, 0)
    this.observer = new MutationObserver(this.refreshCharts)
    this.observer.observe(document.body, { childList: true, subtree: true })
  }

  disconnect() {
    document.removeEventListener("app:theme-changed", this.refreshCharts)
    window.clearTimeout(this.refreshTimer)
    this.observer?.disconnect()
  }

  refreshCharts() {
    if (!window.Chartkick?.charts) return

    const styles = getComputedStyle(document.documentElement)
    const color = (name, fallback) => styles.getPropertyValue(name).trim() || fallback
    const primary = color("--app-primary", "#3368a0")
    const muted = color("--app-muted", "#617178")
    const border = color("--bs-border-color", "#dee2e6")
    const surface = color("--bs-card-bg", "#ffffff")

    // Gráficos de composição precisam de contraste entre as categorias;
    // por isso usam uma paleta própria, independente do tema selecionado.
    const segmentPalette = [
      "#3368a0", "#ee7214", "#2d9596", "#dc3545",
      "#7657a6", "#d977a8", "#198754", "#d6a72c"
    ]

    Object.values(window.Chartkick.charts).forEach((wrapper) => {
      const chart = wrapper.getChartObject?.()
      if (!chart) return

      chart.options.color = muted

      Object.values(chart.options.scales || {}).forEach((scale) => {
        scale.ticks = { ...scale.ticks, color: muted }
        scale.grid = { ...scale.grid, color: border }
        scale.title = { ...scale.title, color: muted }
      })

      if (chart.options.plugins?.legend?.labels) {
        chart.options.plugins.legend.labels.color = muted
      }

      chart.data.datasets.forEach((dataset) => {
        const chartType = chart.config?.type || wrapper.getType?.()
        const isMultiSegment = ["pie", "doughnut", "polarArea"].includes(chartType)

        if (isMultiSegment) {
          const segmentColors = dataset.data.map((_, segmentIndex) => (
            segmentPalette[segmentIndex % segmentPalette.length]
          ))

          dataset.backgroundColor = segmentColors
          dataset.borderColor = surface
          dataset.borderWidth = 2
          return
        }

        const seriesColor = primary
        dataset.borderColor = seriesColor
        dataset.backgroundColor = seriesColor
        dataset.pointBackgroundColor = seriesColor
        dataset.pointBorderColor = seriesColor
      })

      chart.update("none")
    })
  }
}
