import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "field"]

  toggle() {
    this.fieldTarget.classList.toggle("d-none")
    this.buttonTarget.classList.toggle("d-none")
  }

  updateDate(event) {
    const value = event.target.value

    if (value) {
      const date = new Date(value)
      const formatted = date.toLocaleDateString("pt-BR", {
        day: "2-digit",
        month: "2-digit"
      })

      this.buttonTarget.innerText = `📅 ${formatted}`
    }

    this.close()
  }

  updateUsers(event) {
    const selected = Array.from(event.target.selectedOptions)

  if (selected.length > 0) {
    const names = selected
      .map(u => u.text.split(" ")[0]) // pega primeiro nome
      .slice(0, 3)

    this.buttonTarget.innerText = `👤 ${names.join(", ")}`

    if (selected.length > 3) {
      this.buttonTarget.innerText += ` +${selected.length - 3}`
    }
  }

    this.close()
  }

  close() {
    this.fieldTarget.classList.add("d-none")
    this.buttonTarget.classList.remove("d-none")
  }
}