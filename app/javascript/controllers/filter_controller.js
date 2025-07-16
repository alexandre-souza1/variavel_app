import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filterButton", "category"]

  connect() {
    // Inicializa mostrando todos os itens
    this.filter("all")
  }

  filter(event) {
    const filterValue = typeof event === 'string' ? event : event.currentTarget.dataset.filter

    // Remove active class de todos os botões
    this.filterButtonTargets.forEach(btn => btn.classList.remove('active'))

    // Adiciona active class ao botão clicado
    if (typeof event !== 'string') {
      event.currentTarget.classList.add('active')
    }

    // Mostra/esconde documentos baseado no filtro
    this.categoryTargets.forEach(item => {
      if (filterValue === 'all') {
        item.style.display = 'block'
      } else {
        item.style.display = item.dataset.category === filterValue ? 'block' : 'none'
      }
    })
  }
}
