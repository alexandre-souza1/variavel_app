// app/javascript/controllers/radio_button_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]
  static values = { selected: Number }

  connect() {
    // Encontra o input que já está selecionado (se existir)
    const selectedInput = this.inputTargets.find(input => input.checked)

    // Se não encontrou nenhum selecionado, seleciona o primeiro
    if (!selectedInput && this.inputTargets.length > 0) {
      this.inputTargets[0].checked = true
      this.selectButton(this.inputTargets[0].value)
    } else if (selectedInput) {
      this.selectButton(selectedInput.value)
    }
  }

  select(event) {
    const value = event.params.value
    const input = this.inputTargets.find(input => input.value === value.toString())

    if (input) {
      input.checked = true
      this.selectButton(value)
      input.dispatchEvent(new Event('change'))
    }
  }

  selectButton(value) {
    this.buttonTargets.forEach(button => {
      const buttonValue = button.dataset.radioButtonValueParam
      if (parseInt(buttonValue) === parseInt(value)) {
        button.classList.add("active")
        button.classList.remove("btn-outline-primary")
        button.classList.add("btn-primary")
      } else {
        button.classList.remove("active")
        button.classList.add("btn-outline-primary")
        button.classList.remove("btn-primary")
      }
    })
  }
}
