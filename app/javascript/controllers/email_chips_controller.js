import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "hidden", "list", "error"]

  connect() {
    this.emails = this.parse(this.hiddenTarget.value)
    this.render()
  }

  addFromKeydown(event) {
    if (!["Enter", "Tab", ",", ";"].includes(event.key)) return

    if (this.inputTarget.value.trim() === "") return

    event.preventDefault()
    this.addMany(this.inputTarget.value)
  }

  addFromBlur() {
    this.addMany(this.inputTarget.value)
  }

  addFromPaste(event) {
    event.preventDefault()
    this.addMany(event.clipboardData.getData("text"))
  }

  remove(event) {
    const email = event.currentTarget.dataset.email
    this.emails = this.emails.filter((value) => value !== email)
    this.sync()
    this.render()
  }

  addMany(value) {
    const emails = this.parse(value)
    const invalid = emails.filter((email) => !this.validEmail(email))
    const valid = emails.filter((email) => this.validEmail(email))

    valid.forEach((email) => {
      if (!this.emails.includes(email)) this.emails.push(email)
    })

    this.inputTarget.value = invalid.join("; ")
    this.showError(invalid)
    this.sync()
    this.render()
  }

  parse(value) {
    return value
      .split(/[\s,;]+/)
      .map((email) => email.trim())
      .filter(Boolean)
  }

  validEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  }

  sync() {
    this.hiddenTarget.value = this.emails.join("; ")
  }

  render() {
    this.listTarget.innerHTML = ""

    this.emails.forEach((email) => {
      const chip = document.createElement("span")
      chip.className = "email-chip"

      const label = document.createElement("span")
      label.textContent = email

      const button = document.createElement("button")
      button.type = "button"
      button.dataset.action = "email-chips#remove"
      button.dataset.email = email
      button.setAttribute("aria-label", `Remover ${email}`)

      const icon = document.createElement("i")
      icon.className = "bi bi-x"

      button.appendChild(icon)
      chip.append(label, button)
      this.listTarget.appendChild(chip)
    })
  }

  showError(invalid) {
    if (!this.hasErrorTarget) return

    if (invalid.length === 0) {
      this.errorTarget.textContent = ""
      this.errorTarget.classList.add("d-none")
      return
    }

    this.errorTarget.textContent = `E-mail inválido: ${invalid.join(", ")}`
    this.errorTarget.classList.remove("d-none")
  }
}
