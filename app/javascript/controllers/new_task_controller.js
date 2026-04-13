import { Controller } from "@hotwired/stimulus"
import { Collapse } from "bootstrap"

export default class extends Controller {
  static targets = ["wrapper", "button", "title", "form"]

  connect() {
    this.collapse = new Collapse(this.wrapperTarget, {
      toggle: false
    })

    // 🔥 bind pra conseguir remover depois
    this.handleClickOutside = this.handleClickOutside.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)
  }

  toggle() {
    this.collapse.toggle()
    this.buttonTarget.classList.toggle("d-none")

    const isOpen = this.wrapperTarget.classList.contains("show")

    if (isOpen) {
      document.addEventListener("click", this.handleClickOutside)
      document.addEventListener("keydown", this.handleKeydown)

      setTimeout(() => {
        this.titleTarget.focus()
      }, 200)
    } else {
      this.removeListeners()
    }
  }

  isEmpty() {
    return this.titleTarget.value.trim() === ""
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.isEmpty()) {
      this.cancel()
    }
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target) && this.isEmpty()) {
      this.cancel()
    }
  }
  
  cancel() {
    this.resetForm()

    this.collapse.hide()
    this.buttonTarget.classList.remove("d-none")

    this.removeListeners()
  }

  afterSubmit(event) {
    if (event.detail.success) {
      this.cancel()
    }
  }

  resetForm() {
    this.formTarget.reset()

    const selects = this.formTarget.querySelectorAll("select")
    selects.forEach(select => {
      if (select.tomselect) {
        select.tomselect.clear()
      }
    })

    this.resetToggles()
  }

  resetToggles() {
    const toggleControllers = this.element.querySelectorAll("[data-controller='toggle-field']")

    toggleControllers.forEach(el => {
      const button = el.querySelector("[data-toggle-field-target='button']")
      const field = el.querySelector("[data-toggle-field-target='field']")

      if (button) {
        if (button.innerText.includes("📅")) {
          button.innerText = "📅 Definir data"
        } else if (button.innerText.includes("👤")) {
          button.innerText = "👤 Atribuir responsável"
        }
      }

      if (field) field.classList.add("d-none")
      if (button) button.classList.remove("d-none")
    })
  }

  // 🔥 remove listeners (importante pra não bugar)
  removeListeners() {
    document.removeEventListener("click", this.handleClickOutside)
    document.removeEventListener("keydown", this.handleKeydown)
  }
}