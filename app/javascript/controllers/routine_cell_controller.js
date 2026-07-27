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

  edit() {
    this.inputTarget.value = this.rawValueValue || ""

    this.displayTarget.classList.add("d-none")
    this.inputTarget.classList.remove("d-none")

    this.configureInput()

    this.inputTarget.focus()
    this.inputTarget.select()
  }

  connect() {
    this.inputTarget.addEventListener("keydown", this.keydown.bind(this))
    this.inputTarget.addEventListener("blur", this.blur.bind(this))
  }

  keydown(event) {

    if (event.key === "Enter") {
      event.preventDefault()

      const rowOffset = event.shiftKey ? -1 : 1

      this.save().then((saved) => {
        if (saved) {
          this.focusCell(rowOffset, 0)
        }
      })
    }

    if (event.key === "Tab") {
      event.preventDefault()

      const columnOffset = event.shiftKey ? -1 : 1

      this.save().then((saved) => {
        if (saved) {
          this.focusCell(0, columnOffset)
        }
      })
    }

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.focusCell(1, 0)
    }

    if (event.key === "ArrowUp") {
      event.preventDefault()
      this.focusCell(-1, 0)
    }

    if (event.key === "ArrowRight") {
      event.preventDefault()
      this.focusCell(0, 1)
    }

    if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.focusCell(0, -1)
    }

    if (event.key === "Escape") {
      event.preventDefault()
      this.cancel()
    }

  }

  cancel() {

    this.inputTarget.value = this.rawValueValue || ""

    this.inputTarget.classList.add("d-none")

    this.displayTarget.classList.remove("d-none")

  }

  blur() {

    if (this.inputTarget.classList.contains("d-none")) {
      return
    }

    this.save()

  }

  configureInput() {

    this.inputTarget.removeAttribute("inputmode")
    this.inputTarget.removeAttribute("step")

    switch (this.typeValue) {

      case "integer":
        this.inputTarget.inputMode = "numeric"
        break

      case "decimal":
        this.inputTarget.inputMode = "decimal"
        break

      case "percentage":
        this.inputTarget.inputMode = "decimal"
        break

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

  async save() {

    const value = this.inputTarget.value.trim()

    // Não alterou nada
    if (value === (this.rawValueValue || "")) {
      this.cancel()
      return true
    }

    if (!this.validate(value)) {

      this.element.classList.add("routine-cell--error")

      this.inputTarget.focus()

      setTimeout(() => {
        this.element.classList.remove("routine-cell--error")
      }, 800)

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

      this.element.classList.remove("routine-cell--saving")
      this.element.classList.add("routine-cell--error")

      setTimeout(() => {
        this.element.classList.remove("routine-cell--error")
      }, 1000)

      alert("Erro ao salvar.")

      return false
    }

    const data = await response.json()

    this.rawValueValue = data.value

    this.displayTarget.textContent = data.formatted_value

    this.cancel()

    this.element.classList.remove("routine-cell--saving")
    this.element.classList.add("routine-cell--saved")

    setTimeout(() => {
      this.element.classList.remove("routine-cell--saved")
    }, 600)

    return true

  }

}
