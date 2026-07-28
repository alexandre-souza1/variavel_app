import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static targets = [
    "display",
    "input"
  ]

  static values = {
    id: Number,
    rawValue: String,
    type: String
  }

  connect() {
    this.saving = false

    this.inputTarget.addEventListener("keydown", this.keydown.bind(this))
    this.inputTarget.addEventListener("blur", this.blur.bind(this))
  }

  edit() {
    this.inputTarget.value = this.rawValueValue || ""

    this.displayTarget.classList.add("d-none")
    this.inputTarget.classList.remove("d-none")

    this.configureInput()

    this.inputTarget.focus()
    this.inputTarget.select()
  }

  keydown(event) {

    switch (event.key) {

      case "Enter":
        event.preventDefault()

        this.save().then((saved) => {
          if (saved) {
            this.focusCell(event.shiftKey ? -1 : 1, 0)
          }
        })

        break

      case "Tab":
        event.preventDefault()

        this.save().then((saved) => {
          if (saved) {
            this.focusCell(0, event.shiftKey ? -1 : 1)
          }
        })

        break

      case "ArrowDown":
        event.preventDefault()
        this.focusCell(1, 0)
        break

      case "ArrowUp":
        event.preventDefault()
        this.focusCell(-1, 0)
        break

      case "ArrowRight":
        event.preventDefault()
        this.focusCell(0, 1)
        break

      case "ArrowLeft":
        event.preventDefault()
        this.focusCell(0, -1)
        break

      case "Escape":
        event.preventDefault()
        this.cancel()
        break

    }

  }

  blur() {

    if (this.saving) return

    if (this.inputTarget.classList.contains("d-none")) return

    this.save()

  }

  cancel() {

    this.inputTarget.value = this.rawValueValue || ""

    this.inputTarget.classList.add("d-none")
    this.displayTarget.classList.remove("d-none")

  }

  configureInput() {

    this.inputTarget.removeAttribute("inputmode")
    this.inputTarget.removeAttribute("step")

    switch (this.typeValue) {

      case "integer":
        this.inputTarget.inputMode = "numeric"
        break

      case "decimal":
      case "percentage":
      case "currency":
        this.inputTarget.inputMode = "decimal"
        break

      default:
        this.inputTarget.inputMode = "text"

    }

  }

  focusCell(rowOffset, columnOffset) {

    const row = Number(this.element.dataset.row) + rowOffset
    const column = Number(this.element.dataset.column) + columnOffset

    const nextCell = document.querySelector(
      `[data-controller="routine-cell"][data-row="${row}"][data-column="${column}"]`
    )

    if (nextCell) {
      nextCell.click()
    }

  }

  validate(value) {

    switch (this.typeValue) {

      case "integer":
        return /^-?\d+$/.test(value)

      case "decimal":
      case "percentage":
      case "currency":
        return /^-?\d+([.,]\d+)?$/.test(value)

      default:
        return true

    }

  }

  showError() {

    this.saving = false

    this.element.classList.remove("routine-cell--saving")
    this.element.classList.add("routine-cell--error")

    setTimeout(() => {
      this.element.classList.remove("routine-cell--error")
    }, 800)

  }

  finishEdition() {

    this.cancel()

    this.saving = false

    this.element.classList.remove("routine-cell--saving")
    this.element.classList.add("routine-cell--saved")

    setTimeout(() => {
      this.element.classList.remove("routine-cell--saved")
    }, 600)

  }

  async save() {

    if (this.saving) return false

    this.saving = true

    const value = this.inputTarget.value.trim()

    // Não alterou nada
    if (value === (this.rawValueValue || "")) {
      this.saving = false
      this.cancel()
      return true
    }

    if (!this.validate(value)) {
      this.showError()
      this.inputTarget.focus()
      return false
    }

    this.element.classList.add("routine-cell--saving")

    const response = await fetch(`/routine_values/${this.idValue}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector(
          "meta[name='csrf-token']"
        ).content,
        "Accept": "application/json"
      },
      body: JSON.stringify({
        routine_value: {
          value: value
        }
      })
    })

    if (!response.ok) {

      alert("Erro ao salvar.")

      this.showError()

      return false

    }

    const data = await response.json()

    this.rawValueValue = data.value
    this.displayTarget.textContent = data.formatted_value

    this.finishEdition()

    return true

  }

}
