import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sectorButton", "categoryButton", "category", "item"]

  connect() {
    const params = new URLSearchParams(window.location.search)
    this.sector = this.validValue(
      params.get("sector"),
      this.sectorButtonTargets,
      "filterSector"
    )
    this.category = this.validValue(
      params.get("category"),
      this.categoryButtonTargets,
      "filterCategory"
    )
    this.popStateHandler = () => this.loadFromUrl()
    window.addEventListener("popstate", this.popStateHandler)
    this.applyFilters()
  }

  disconnect() {
    window.removeEventListener("popstate", this.popStateHandler)
  }

  filterSector(event) {
    this.sector = event.currentTarget.dataset.filterSector
    this.updateUrl()
    this.applyFilters()
  }

  filterCategory(event) {
    this.category = event.currentTarget.dataset.filterCategory
    this.updateUrl()
    this.applyFilters()
  }

  loadFromUrl() {
    const params = new URLSearchParams(window.location.search)
    this.sector = this.validValue(
      params.get("sector"),
      this.sectorButtonTargets,
      "filterSector"
    )
    this.category = this.validValue(
      params.get("category"),
      this.categoryButtonTargets,
      "filterCategory"
    )
    this.applyFilters()
  }

  validValue(value, buttons, attribute) {
    if (!value) return "all"

    return buttons.some((button) => button.dataset[attribute] === value)
      ? value
      : "all"
  }

  updateUrl() {
    const url = new URL(window.location.href)

    if (this.sector === "all") url.searchParams.delete("sector")
    else url.searchParams.set("sector", this.sector)

    if (this.category === "all") url.searchParams.delete("category")
    else url.searchParams.set("category", this.category)

    window.history.pushState({}, "", url)
  }

  applyFilters() {
    this.updateButtons(this.sectorButtonTargets, this.sector, "filterSector")
    this.updateButtons(this.categoryButtonTargets, this.category, "filterCategory")

    this.itemTargets.forEach((item) => {
      const matchesSector = this.sector === "all" || item.dataset.sector === this.sector
      const matchesCategory = this.category === "all" || item.dataset.category === this.category

      item.hidden = !(matchesSector && matchesCategory)
    })

    this.categoryTargets.forEach((category) => {
      category.hidden = !category.querySelector(
        '[data-downloads-filter-target="item"]:not([hidden])'
      )
    })
  }

  updateButtons(buttons, activeValue, action) {
    buttons.forEach((button) => {
      const active = button.dataset[action === "filterSector" ? "filterSector" : "filterCategory"] === activeValue

      button.classList.toggle("active", active)
      button.setAttribute("aria-pressed", active)
      if (button.getAttribute("role") === "tab") {
        button.setAttribute("aria-selected", active)
      }
    })
  }
}
