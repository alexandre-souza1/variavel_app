import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "item", "group", "empty"]

  connect() {
    this.filter()
  }

  filter() {
    const query = this.normalize(this.queryTarget.value)
    let visibleCount = 0

    this.itemTargets.forEach((item) => {
      const matches = this.normalize(item.dataset.searchText || "").includes(query)

      item.classList.toggle("filter-hidden", !matches)

      if (matches && !item.classList.contains("d-none")) {
        visibleCount += 1
      }
    })

    this.groupTargets.forEach((group) => {
      const hasVisibleItem = this.itemTargets.some((item) => {
        return group.contains(item) &&
          !item.classList.contains("filter-hidden") &&
          !item.classList.contains("d-none")
      })

      group.classList.toggle("filter-hidden", query.length > 0 && !hasVisibleItem)
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("d-none", visibleCount > 0)
    }
  }

  normalize(value) {
    return value
      .toString()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim()
  }
}
