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

    Object.entries(window.Chartkick.charts).forEach(([chartId, wrapper]) => {
      const chart = wrapper.getChartObject?.()
      if (!chart) return

      const aiComparison = document.getElementById(chartId)?.closest(".ai-settings-page")
      const chartMuted = aiComparison ? color("--bs-secondary-color", muted) : muted
      chart.options.color = chartMuted

      Object.values(chart.options.scales || {}).forEach((scale) => {
        scale.ticks = { ...scale.ticks, color: chartMuted }
        scale.grid = { ...scale.grid, color: border }
        scale.title = { ...scale.title, color: chartMuted }
      })

      if (chart.options.plugins?.legend?.labels) {
        chart.options.plugins.legend.labels.color = chartMuted
      }

      chart.data.datasets.forEach((dataset, datasetIndex) => {
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

        const seriesColor = aiComparison && chart.data.datasets.length > 1 ? segmentPalette[datasetIndex % segmentPalette.length] : primary
        dataset.borderColor = seriesColor
        dataset.backgroundColor = seriesColor
        dataset.pointBackgroundColor = seriesColor
        dataset.pointBorderColor = seriesColor
      })

      // Interrompe a animação anterior para ela não repintar a paleta antiga.
      chart.stop()
      chart.update("none")
    })
  }
};
