import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "item", "cloud", "empty", "resultCount"]

  connect() {
    if (!this.hasCloudTarget) return

    this.connected = true
    this.items = this.itemTargets
    this.maxCount = Math.max(...this.items.map(item => Number(item.dataset.usageCount) || 0), 1)
    this.filter()
    this.resizeObserver = new ResizeObserver(([entry]) => {
      if (this.width === entry.contentRect.width) return
      this.width = entry.contentRect.width
      this.scheduleLayout()
    })
    this.resizeObserver.observe(this.cloudTarget)
    document.fonts.ready.then(() => { if (this.connected) this.scheduleLayout() })
  }

  disconnect() {
    this.connected = false
    this.resizeObserver?.disconnect()
    cancelAnimationFrame(this.frame)
  }

  filter() {
    const query = this.normalize(this.queryTarget.value)
    let visibleCount = 0

    this.items.forEach(item => {
      const matches = this.normalize(item.dataset.labelName).includes(query)
      item.classList.toggle("is-hidden", !matches)
      if (matches) visibleCount += 1
    })

    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("d-none", visibleCount > 0)
    this.cloudTarget.classList.toggle("d-none", visibleCount === 0)
    this.resultCountTarget.textContent = `${visibleCount} ${visibleCount === 1 ? "label encontrada" : "labels encontradas"}`
    this.scheduleLayout()
  }

  scheduleLayout() {
    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => this.layout())
  }

  layout() {
    const cloud = this.cloudTarget
    const width = cloud.clientWidth - 40
    if (width <= 0) return
    const visible = this.items.filter(item => !item.classList.contains("is-hidden"))
      .sort((a, b) => Number(b.dataset.usageCount) - Number(a.dataset.usageCount) ||
        b.dataset.labelName.length - a.dataset.labelName.length)
    if (!visible.length) return

    cloud.classList.remove("is-positioned")
    const mobile = width < 500
    const words = visible.map((item, index) => {
      Object.assign(item.style, { width: "", height: "", left: "", top: "" })
      const text = item.querySelector(".action-plan-label-cloud__word")
      text.style.whiteSpace = "nowrap"
      const weight = Math.sqrt((Number(item.dataset.usageCount) || 0) / this.maxCount)
      const size = (mobile ? 14 : 18) + weight * (mobile ? 28 : 48)
      const vertical = visible.length > 3 && index % 3 === 1 && item.dataset.labelName.length < 30
      item.style.setProperty("--word-angle", vertical ? "-90deg" : "0deg")
      return { item, text, size, vertical }
    })

    // Measure the actual font, then pack from the centre along a spiral.
    // Bounding boxes include a small gap so words never overlap.
    for (let attempt = 0; attempt < 9; attempt += 1) {
      const scale = 0.88 ** attempt
      const measured = words.map(word => {
        word.item.style.setProperty("--word-size", `${Math.max(12, word.size * scale)}px`)
        const textWidth = word.text.offsetWidth
        const textHeight = word.text.offsetHeight
        return { ...word, width: (word.vertical ? textHeight : textWidth) + 8,
          height: (word.vertical ? textWidth : textHeight) + 8 }
      })
      const area = measured.reduce((sum, word) => sum + word.width * word.height, 0)
      const height = Math.max(mobile ? 260 : 340, Math.ceil(area * 1.7 / width),
        ...measured.map(word => word.height + 20))
      const placed = []
      for (const word of measured) {
        const position = this.position(word, placed, width, height)
        if (!position) break
        placed.push({ ...word, ...position })
      }
      if (placed.length !== measured.length) continue

      const left = Math.min(...placed.map(word => word.x))
      const right = Math.max(...placed.map(word => word.x + word.width))
      const top = Math.min(...placed.map(word => word.y))
      const bottom = Math.max(...placed.map(word => word.y + word.height))
      const offsetX = (width - right + left) / 2 - left + 20
      const offsetY = (height - bottom + top) / 2 - top + 20
      placed.forEach(word => Object.assign(word.item.style, {
        left: `${word.x + offsetX}px`, top: `${word.y + offsetY}px`,
        width: `${word.width}px`, height: `${word.height}px`
      }))
      cloud.style.height = `${height + 40}px`
      cloud.classList.add("is-positioned")
      return
    }

    // Keep every label accessible even with unusually long names or many labels.
    cloud.style.height = "auto"
    words.forEach(word => { word.text.style.whiteSpace = "" })
  }

  position(word, placed, width, height) {
    for (let step = 0; step < 6000; step += 1) {
      const angle = step * 0.3
      const radius = step * 0.22
      const x = width / 2 + Math.cos(angle) * radius * 1.35 - word.width / 2
      const y = height / 2 + Math.sin(angle) * radius - word.height / 2
      if (x < 0 || y < 0 || x + word.width > width || y + word.height > height) continue
      if (placed.some(other => x < other.x + other.width && x + word.width > other.x &&
        y < other.y + other.height && y + word.height > other.y)) continue
      return { x, y }
    }
    return null
  }

  clear() {
    this.queryTarget.value = ""
    this.queryTarget.focus()
    this.filter()
  }

  manage(event) {
    const enabled = this.cloudTarget.classList.toggle("is-managing")
    event.currentTarget.setAttribute("aria-pressed", String(enabled))
    event.currentTarget.querySelector("span").textContent = enabled ? "Concluir" : "Gerenciar"
  }

  normalize(value) {
    return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase().trim()
  }
}
