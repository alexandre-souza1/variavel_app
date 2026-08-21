import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filterButton", "category"]

  connect() {
    this.setFilter("all")
  }

  filter(event) {
    const filterValue = event.currentTarget.dataset.filter

    this.setFilter(filterValue)
  }

  setFilter(filterValue) {
    // Atualiza botão ativo
    this.filterButtonTargets.forEach((button) => {
      const isActive = button.dataset.filter === filterValue

      button.classList.toggle("active", isActive)
      button.setAttribute("aria-pressed", isActive)
    })

    // Mostra/esconde categorias
    this.categoryTargets.forEach((category) => {
      const shouldShow =
        filterValue === "all" ||
        category.dataset.category === filterValue

      category.hidden = !shouldShow
    })
  }
}
