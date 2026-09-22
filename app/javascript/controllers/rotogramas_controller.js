import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { cities: Array }
  static targets = ["search", "workspace", "mode", "filterButton", "city", "list", "count", "empty", "map", "mapPanel", "mapNotice", "selection", "preview", "selectedName", "selectedDetails", "selectedStar", "openButton", "reader", "readerTitle", "download", "previous", "next", "pageLabel", "zoomLabel", "readerContent", "pageImage", "loading", "imageError"]

  connect() {
    this.active = true
    this.favorites = this.readStorage("favorites")
    this.recent = this.readStorage("recent")
    this.activeFilter = "all"
    this.viewMode = "map"
    this.selected = null
    this.filterButtonTargets.forEach(button => button.setAttribute("aria-pressed", button.dataset.filter === "all"))
    this.changeModeTo("map")
    this.filter()
    this.initializeMap()
  }

  disconnect() {
    this.active = false
    this.teardown()
  }

  beforeCache() {
    this.active = false
    this.teardown()
    this.selectionTarget.hidden = true
  }

  teardown() {
    if (this.readerTarget.open) this.closeReader()
    this.resizeObserver?.disconnect()
    this.map?.remove()
    this.map = null
  }

  readStorage(key) {
    try {
      const value = JSON.parse(localStorage.getItem(`rotogramas:${key}`) || "[]")
      return Array.isArray(value) ? value.filter(id => this.citiesValue.some(city => city.id === id)) : []
    } catch { return [] }
  }

  saveStorage(key, value) {
    try { localStorage.setItem(`rotogramas:${key}`, JSON.stringify(value)) } catch { /* Session remains usable when storage is unavailable. */ }
  }

  normalize(value) {
    return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()
  }

  filter() {
    const query = this.normalize(this.searchTarget.value)
    this.filtered = this.citiesValue.filter(city => {
      const matches = this.normalize(`${city.name} ${city.aliases}`).includes(query)
      return matches && (this.activeFilter === "all" || (this.activeFilter === "favorites" ? this.favorites : this.recent).includes(city.id))
    })
    if (this.activeFilter === "recent") this.filtered.sort((a, b) => this.recent.indexOf(a.id) - this.recent.indexOf(b.id))
    else this.filtered.sort((a, b) => a.name.localeCompare(b.name, "pt-BR"))
    this.cityTargets.forEach(card => {
      const index = this.filtered.findIndex(city => city.id === card.dataset.id)
      card.hidden = index < 0
      card.style.order = index
      card.classList.toggle("is-selected", card.dataset.id === this.selected?.id)
      this.updateStar(card.querySelector(".roto-star"), card.dataset.id)
    })
    this.countTarget.textContent = `${this.filtered.length} ${this.filtered.length === 1 ? "localidade disponível" : "localidades disponíveis"}`
    this.emptyTarget.hidden = this.filtered.length > 0
    this.emptyTarget.textContent = query ? "Nenhuma localidade encontrada. Tente outro nome." : this.activeFilter === "favorites" ? "Toque na estrela de uma cidade para encontrá-la aqui." : "Os rotogramas que você abrir aparecerão aqui."
    if (this.selected && !this.filtered.some(city => city.id === this.selected.id)) this.clearSelection()
    this.renderMarkers()
    if (query && this.filtered.length) this.fitMap()
  }

  changeFilter(event) {
    this.activeFilter = event.currentTarget.dataset.filter
    this.filterButtonTargets.forEach(button => button.setAttribute("aria-pressed", button.dataset.filter === this.activeFilter))
    this.filter()
    this.fitMap()
  }

  changeMode(event) { this.changeModeTo(event.currentTarget.dataset.mode) }

  changeModeTo(mode) {
    this.viewMode = mode
    this.workspaceTarget.dataset.mode = mode
    this.modeTargets.forEach(button => button.setAttribute("aria-pressed", button.dataset.mode === mode))
    if (mode === "map") requestAnimationFrame(() => {
      if (!this.active) return
      this.map?.invalidateSize()
      this.renderMarkers()
    })
  }

  toggleFavorite(event) {
    const id = event.currentTarget.dataset.id || this.selected?.id
    if (!id) return
    this.favorites = this.favorites.includes(id) ? this.favorites.filter(item => item !== id) : [...this.favorites, id]
    this.saveStorage("favorites", this.favorites)
    this.filter()
    if (this.selected) this.updateStar(this.selectedStarTarget, this.selected.id)
  }

  updateStar(button, id) {
    const favorite = this.favorites.includes(id)
    button.textContent = favorite ? "★" : "☆"
    button.setAttribute("aria-pressed", favorite)
    const name = this.citiesValue.find(city => city.id === id)?.name || "cidade"
    button.setAttribute("aria-label", `${favorite ? "Remover dos favoritos:" : "Favoritar"} ${name}`)
  }

  async initializeMap() {
    try {
      const L = await import("leaflet")
      if (!this.active) return
      this.L = L
      this.map = L.map(this.mapTarget, { zoomControl: false, scrollWheelZoom: false, minZoom: 6, maxZoom: 18 })
      L.control.zoom({ position: "topright" }).addTo(this.map)
      const tiles = L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>'
      }).addTo(this.map)
      tiles.on("tileerror", () => { this.mapNoticeTarget.hidden = false })
      tiles.on("tileload", () => { this.mapNoticeTarget.hidden = true })
      this.markerLayer = L.layerGroup().addTo(this.map)
      this.map.on("zoomend moveend", () => this.renderMarkers())
      this.fitMap()
      this.renderMarkers()
      this.resizeObserver = new ResizeObserver(() => {
        this.map?.invalidateSize()
        this.renderMarkers()
      })
      this.resizeObserver.observe(this.mapTarget)
    } catch (error) {
      this.mapNoticeTarget.hidden = false
    }
  }

  fitMap() {
    if (!this.map) return
    const cities = this.filtered.length ? this.filtered : this.citiesValue
    this.map.fitBounds(cities.map(city => [city.lat, city.lng]), { padding: [45, 65], maxZoom: cities.length === 1 ? 12 : 10, animate: false })
  }

  renderMarkers() {
    if (!this.map || !this.markerLayer || !this.map._loaded) return
    const L = this.L
    this.markerLayer.clearLayers()
    // Group nearby destinations in screen space so every pin remains tappable.
    const groups = []
    this.filtered.forEach(city => {
      const point = this.map.latLngToContainerPoint([city.lat, city.lng])
      const group = groups.find(item => item.point.distanceTo(point) < 46)
      if (group) group.cities.push(city)
      else groups.push({ point, cities: [city] })
    })
    groups.forEach(group => {
      const cities = group.cities
      const clustered = cities.length > 1
      const lat = cities.reduce((sum, city) => sum + city.lat, 0) / cities.length
      const lng = cities.reduce((sum, city) => sum + city.lng, 0) / cities.length
      const selected = cities.some(city => city.id === this.selected?.id)
      const icon = L.divIcon({
        className: "roto-marker",
        html: `<div class="roto-pin ${clustered ? "is-cluster" : ""} ${selected ? "is-selected" : ""}"><span>${clustered ? cities.length : "●"}</span></div>`,
        iconSize: clustered ? [42, 42] : [34, 34], iconAnchor: clustered ? [21, 21] : [17, 30]
      })
      const title = clustered ? `${cities.length} localidades. Aproximar mapa` : cities[0].name
      const marker = L.marker([lat, lng], { icon, title, alt: title, keyboard: true }).addTo(this.markerLayer)
      const tooltip = document.createElement("span")
      tooltip.textContent = clustered ? cities.map(city => city.name).join(" · ") : cities[0].name
      marker.bindTooltip(tooltip, { direction: "top", offset: [0, -24] })
      marker.on("click", () => {
        if (clustered) this.map.fitBounds(cities.map(city => [city.lat, city.lng]), { padding: [65, 65], maxZoom: 15, animate: false })
        else this.selectCity(cities[0].id, true)
      })
    })
  }

  select(event) { this.selectCity(event.currentTarget.dataset.id) }
  selectFirst(event) { event.preventDefault(); if (this.filtered[0]) this.selectCity(this.filtered[0].id) }

  selectCity(id, fromMap = false) {
    this.selected = this.citiesValue.find(city => city.id === id)
    if (!this.selected) return
    if (this.viewMode === "list") { this.openReader(); return }
    const city = this.selected
    this.selectedNameTarget.textContent = city.name
    this.selectedDetailsTarget.textContent = `${city.context} · ${city.pages} páginas · PDF ${(city.bytes / 1048576).toFixed(1).replace(".", ",")} MB`
    this.previewTarget.src = `/rotogramas/${city.id}/previa.jpg`
    this.selectedStarTarget.dataset.id = city.id
    this.updateStar(this.selectedStarTarget, city.id)
    this.selectionTarget.hidden = false
    this.cityTargets.forEach(card => card.classList.toggle("is-selected", card.dataset.id === id))
    if (this.map) {
      this.map.setView([city.lat, city.lng], Math.max(this.map.getZoom(), 11), { animate: false })
      // Reserve space below the pin for the destination card.
      this.map.panBy([0, this.selectionTarget.offsetHeight / 2], { animate: false })
    }
    this.renderMarkers()
    if (!fromMap && window.matchMedia("(max-width: 700px)").matches) this.mapPanelTarget.scrollIntoView({ block: "start", behavior: "instant" })
    this.openButtonTarget.focus({ preventScroll: true })
  }

  clearSelection() {
    this.selected = null
    this.selectionTarget.hidden = true
    this.cityTargets.forEach(card => card.classList.remove("is-selected"))
    this.renderMarkers()
  }

  openReader() {
    if (!this.selected) return
    this.readingCity = this.selected
    this.page = 1
    this.scale = 1
    this.readerTitleTarget.textContent = this.readingCity.name
    this.downloadTarget.href = `/rotogramas/${this.readingCity.id}/documento.pdf`
    this.downloadTarget.download = `rotograma-${this.readingCity.id}.pdf`
    this.downloadTarget.setAttribute("aria-label", `Baixar PDF de ${this.readingCity.name}`)
    this.recent = [this.readingCity.id, ...this.recent.filter(id => id !== this.readingCity.id)].slice(0, 8)
    this.saveStorage("recent", this.recent)
    this.bodyOverflow = document.body.style.overflow
    document.body.style.overflow = "hidden"
    this.readerTarget.showModal()
    this.showPage()
  }

  changePage(event) {
    this.page = Math.min(this.readingCity.pages, Math.max(1, this.page + Number(event.currentTarget.dataset.step)))
    this.showPage()
  }

  showPage() {
    this.pageLabelTarget.textContent = `${this.page} / ${this.readingCity.pages}`
    this.previousTarget.disabled = this.page === 1
    this.nextTarget.disabled = this.page === this.readingCity.pages
    this.loadingTarget.hidden = false
    this.imageErrorTarget.hidden = true
    this.pageImageTarget.hidden = true
    this.pageImageTarget.alt = `Rotograma de ${this.readingCity.name}, página ${this.page} de ${this.readingCity.pages}`
    this.pageImageTarget.src = `/rotogramas/${this.readingCity.id}/pagina-${String(this.page).padStart(2, "0")}.jpg`
    this.applyZoom()
    this.readerContentTarget.scrollTo(0, 0)
  }

  imageLoaded() { this.loadingTarget.hidden = true; this.pageImageTarget.hidden = false }
  imageFailed() { this.loadingTarget.hidden = true; this.imageErrorTarget.hidden = false; this.pageImageTarget.hidden = true }
  zoom(event) { this.scale = Math.min(6, Math.max(1, this.scale + Number(event.currentTarget.dataset.step))); this.applyZoom() }
  resetZoom() { this.scale = 1; this.applyZoom() }
  applyZoom() { this.pageImageTarget.style.width = `${this.scale * 100}%`; this.zoomLabelTarget.textContent = `${Math.round(this.scale * 100)}%` }

  async fullscreen() {
    try {
      if (document.fullscreenElement) await document.exitFullscreen()
      else if (this.readerTarget.requestFullscreen) await this.readerTarget.requestFullscreen()
    } catch { /* The mobile dialog already fills the available viewport. */ }
  }

  closeReader() {
    if (document.fullscreenElement === this.readerTarget) document.exitFullscreen().catch(() => {})
    this.readerTarget.close()
    this.restoreBody()
  }

  restoreBody() {
    if (this.bodyOverflow !== undefined) { document.body.style.overflow = this.bodyOverflow; this.bodyOverflow = undefined }
  }

  readerClosed() {
    this.restoreBody()
    if (this.activeFilter === "recent") this.filter()
  }
}
