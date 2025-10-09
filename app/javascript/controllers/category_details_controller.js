import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { id: Number }

  show(event) {
    const categoryId = event.currentTarget.dataset.categoryDetailsIdValue
    this.loadCategory(categoryId, 1)
  }

  changePage(event) {
    const page = event.currentTarget.dataset.page
    const categoryId = this.idValue
    this.loadCategory(categoryId, page)
  }

  loadCategory(categoryId, page) {
    const container = document.getElementById("category-details-container")
    this.idValue = categoryId

    container.innerHTML = `
      <div class="text-center py-4">
        <div class="spinner-border text-primary" role="status"></div>
        <p class="text-muted mt-2">Carregando...</p>
      </div>
    `

    fetch(`/admin/budget_categories/${categoryId}/expenses?page=${page}`)
      .then(response => response.text())
      .then(html => {
        container.innerHTML = html
        container.scrollIntoView({ behavior: "smooth" })
      })
      .catch(() => {
        container.innerHTML = `
          <div class="alert alert-danger text-center">
            Erro ao carregar os dados. Tente novamente.
          </div>
        `
      })
  }
}
