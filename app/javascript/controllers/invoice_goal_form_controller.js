import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sector", "category", "empty"]
  static values = { sector: String }

  connect() {
    this.filter()
  }

  filter() {
    const sector = this.hasSectorTarget ? this.sectorTarget.value : this.sectorValue
    let count = 0
    this.categoryTargets.forEach((category) => {
      const visible = category.dataset.sector === sector
      category.hidden = !visible
      const checkbox = category.querySelector("input")
      checkbox.disabled = !visible
      if (visible) count += 1
    })
    this.emptyTarget.hidden = count > 0
  }
}
