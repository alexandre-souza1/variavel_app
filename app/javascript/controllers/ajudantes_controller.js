import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["ajudante1", "ajudante2", "fatorInfo"]

  connect() {
    this.updateOptions()
    this.updateFatorInfo()
  }

  selectChanged() {
    this.updateOptions()
    this.updateFatorInfo()
  }

  updateOptions() {
    const val1 = this.ajudante1Target.value
    const val2 = this.ajudante2Target.value

    Array.from(this.ajudante1Target.options).forEach(option => {
      // Só desabilita se for igual ao ajudante 2 e diferente de "0"
      option.disabled = (option.value !== "0" && option.value === val2)
    })

    Array.from(this.ajudante2Target.options).forEach(option => {
      // Só desabilita se for igual ao ajudante 1 e diferente de "0"
      option.disabled = (option.value !== "0" && option.value === val1)
    })
  }

  updateFatorInfo() {
    const ajudante1 = this.ajudante1Target.value
    const ajudante2 = this.ajudante2Target.value

    let count = 0
    if (ajudante1 != "0" && ajudante1 != "") count++
    if (ajudante2 != "0" && ajudante2 != "") count++

    let mensagem = ""

    switch (count) {
      case 0:
        mensagem = "⚠️ Sem ajudantes selecionados, o fator do seu mapa será 0."
        break
      case 1:
        mensagem = "✔️ 1 ajudante selecionado, o fator do mapa será 1.0."
        break
      case 2:
        mensagem = "✔️ 2 ajudantes selecionados, o fator do mapa será 2.0."
        break
    }

    this.fatorInfoTarget.innerText = mensagem
  }
}
