import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "hidden"]

  connect() {
    // Se já tiver valor (edit), formata na entrada
    if (this.hiddenTarget.value) {
      this.inputTarget.value = this.formatBRL(this.hiddenTarget.value)
    }
  }

  format(event) {
    let value = event.target.value.replace(/\D/g, "") // só números

    if (value === "") {
      this.inputTarget.value = ""
      this.hiddenTarget.value = ""
      return
    }

    value = (parseInt(value, 10) / 100).toFixed(2)

    this.hiddenTarget.value = value
    this.inputTarget.value = this.formatBRL(value)
  }

  formatBRL(value) {
    return new Intl.NumberFormat("pt-BR", {
      style: "currency",
      currency: "BRL"
    }).format(value)
  }
}
