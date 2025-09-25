import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cnpj", "name"]

  // Método chamado quando o campo CNPJ perde o foco
  fetchName() {
    const cnpj = this.cnpjTarget.value.replace(/\D/g, "")

    if (cnpj.length !== 14) {
      console.warn("CNPJ inválido")
      return
    }

    fetch(`/suppliers/search_cnpj?cnpj=${cnpj}`)
      .then(res => {
        if (!res.ok) throw new Error(`Erro na requisição: ${res.status}`)
        return res.json()
      })
      .then(data => {
        if (data.name) {
          this.nameTarget.value = data.name
        } else if (data.error) {
          console.warn("Erro API:", data.error)
        }
      })
      .catch(err => {
        console.error("Erro ao buscar CNPJ:", err)
      })
  }
}
