import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "item", "cloud", "empty", "resultCount"]

  connect() {
    if (!this.hasQueryTarget) return

    this.items = this.itemTargets
    this.prepareItems()
    this.filter()
  }

  prepareItems() {
    const maxCount = Math.max(...this.items.map(item => Number(item.dataset.usageCount) || 0), 1)
    const offsets = [0, -0.22, 0.18, -0.1, 0.28, -0.16]

    this.items.forEach((item, index) => {
      const count = Number(item.dataset.usageCount) || 0
      const scale = 0.9 + (Math.sqrt(count) / Math.sqrt(maxCount)) * 0.58

      item.style.setProperty("--label-scale", scale.toFixed(2))
      item.style.setProperty("--cloud-offset", `${offsets[index % offsets.length]}rem`)

    })
  }

  filter() {
    const query = this.queryTarget.value.trim().toLocaleLowerCase()
    let visibleCount = 0

    this.items.forEach(item => {
      const matches = item.dataset.labelName.toLocaleLowerCase().includes(query)
      item.classList.toggle("is-hidden", !matches)
      if (matches) visibleCount += 1
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("d-none", visibleCount > 0)
    }
    this.resultCountTarget.textContent = `${visibleCount} ${visibleCount === 1 ? "label encontrada" : "labels encontradas"}`
  }

  clear() {
    this.queryTarget.value = ""
    this.queryTarget.focus()
    this.filter()
  }

}
