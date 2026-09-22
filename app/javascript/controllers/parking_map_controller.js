import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "result", "space", "listItem", "mapPanel", "listPanel", "mode", "viewport", "frame", "canvas"]

  connect() {
    this.scale = window.innerWidth < 700 ? 0.85 : Math.min(1, this.viewportTarget.clientWidth / 1600)
    this.resize = new ResizeObserver(() => this.applyScale())
    this.resize.observe(this.viewportTarget)
    this.applyScale()
    this.search()
  }

  disconnect() { this.resize?.disconnect() }
  beforeCache() { this.resize?.disconnect() }

  mode(event) {
    if (this.element.dataset.editing === "true" && event.currentTarget.dataset.mode === "list") return
    this.setMode(event.currentTarget.dataset.mode)
  }

  setMode(mode) {
    this.mapPanelTarget.hidden = mode !== "map"
    this.listPanelTarget.hidden = mode !== "list"
    this.modeTargets.forEach(button => button.setAttribute("aria-pressed", button.dataset.mode === mode))
    if (mode === "map") this.applyScale()
  }

  search() {
    const query = this.searchTarget.value.toUpperCase().replace(/[^A-Z0-9]/g, "")
    let found = []
    this.spaceTargets.forEach(space => {
      const plate = space.querySelector(".parking-vehicle")?.dataset.plate || ""
      const matches = !query || plate.includes(query) || Number(query) === Number(space.dataset.slot)
      space.classList.toggle("is-match", !!query && matches)
      space.classList.toggle("is-muted", !!query && !matches)
      if (matches) found.push(space)
    })
    this.listItemTargets.forEach(item => {
      item.hidden = !!query && !item.dataset.plate.includes(query) && Number(query) !== Number(item.dataset.slot)
    })
    this.resultTarget.textContent = !query ? "Busque uma placa para destacar sua vaga no mapa." : found.length ? `${found.length} ${found.length === 1 ? "vaga encontrada" : "vagas encontradas"}.` : "Nenhuma vaga encontrada para essa busca."
    if (query && found.length === 1 && !this.mapPanelTarget.hidden) {
      const space = found[0]
      const viewport = this.viewportTarget.getBoundingClientRect(), rect = space.getBoundingClientRect()
      this.viewportTarget.scrollBy({ left: rect.left - viewport.left - (viewport.width - rect.width) / 2, top: rect.top - viewport.top - (viewport.height - rect.height) / 2, behavior: "instant" })
    }
  }

  zoom(event) { this.scale = Math.min(1.5, Math.max(0.15, this.scale + Number(event.currentTarget.dataset.step))); this.applyScale() }
  fit() { this.scale = Math.min(1, this.viewportTarget.clientWidth / 1600); this.applyScale(); this.viewportTarget.scrollTo(0, 0) }
  applyScale() {
    this.canvasTarget.style.transform = `scale(${this.scale})`
    this.frameTarget.style.width = `${1600 * this.scale}px`
    this.frameTarget.style.height = `${this.canvasTarget.offsetHeight * this.scale}px`
  }
}
