import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { showFlash } from "controllers/flash_controller"

export default class extends Controller {
  connect() {
    this.element.noValidate = true
    this.errorSequence = 0
    this.updateCodeRequirement()
  }

  field(name) {
    return this.element.elements.namedItem(name)
  }

  updateCodeRequirement() {
    const category = this.field("invoice[budget_category_id]").selectedOptions[0]
    this.field("invoice[code]").required = category?.dataset.codeOptional !== "true"
  }

  clearFieldError(event) {
    this.updateCodeRequirement()
    this.removeFieldError(event.target)
  }

  removeFieldError(field) {
    const id = field.dataset.invoiceErrorId
    if (!id) return
    this.element.querySelector(`#${id}`)?.remove()
    field.classList.remove("is-invalid")
    field.removeAttribute("aria-invalid")
    const descriptions = (field.getAttribute("aria-describedby") || "").split(" ").filter((value) => value && value !== id)
    if (descriptions.length) field.setAttribute("aria-describedby", descriptions.join(" "))
    else field.removeAttribute("aria-describedby")
    delete field.dataset.invoiceErrorId
  }

  clearErrors() {
    this.element.querySelectorAll("[data-invoice-error-id]").forEach((field) => this.removeFieldError(field))
  }

  showFieldError(field, message) {
    if (!field || field.disabled) return false
    this.removeFieldError(field)
    const feedback = document.createElement("div")
    feedback.id = `invoice-field-error-${++this.errorSequence}`
    feedback.className = "invalid-feedback d-block"
    feedback.textContent = message
    field.dataset.invoiceErrorId = feedback.id
    field.classList.add("is-invalid")
    field.setAttribute("aria-invalid", "true")
    field.setAttribute("aria-describedby", [field.getAttribute("aria-describedby"), feedback.id].filter(Boolean).join(" "))
    const control = field.tomselect?.wrapper || field
    control.insertAdjacentElement("afterend", feedback)
    return true
  }

  focusFirstError() {
    const field = this.element.querySelector("[data-invoice-error-id]")
    if (!field) return
    const control = field.tomselect?.wrapper || field
    control.scrollIntoView({ block: "center", behavior: "smooth" })
    if (field.tomselect) field.tomselect.focus()
    else field.focus({ preventScroll: true })
  }

  validate() {
    this.clearErrors()
    this.updateCodeRequirement()
    let valid = true
    this.element.querySelectorAll("input[required], select[required]").forEach((field) => {
      if (field.disabled || field.closest(".nested-fields")?.style.display === "none") return
      let message
      if (!field.value.trim()) {
        message = field.tagName === "SELECT" ? "Selecione uma opção." : "Preencha este campo."
      } else if (!field.validity.valid) {
        message = "Informe um valor válido."
      } else if (field.name.endsWith("[amount]")) {
        const value = field.value.trim()
        if (!/^(?:\d{1,3}(?:\.\d{3})*|\d+)(?:,\d+)?$/.test(value) && !/^\d+(?:\.\d+)?$/.test(value)) {
          message = "Informe um valor maior ou igual a zero."
        }
      }
      if (message) {
        this.showFieldError(field, message)
        valid = false
      }
    })

    const category = this.field("invoice[budget_category_id]").selectedOptions[0]
    const purchaser = this.field("invoice[purchaser_id]")
    const sector = purchaser.selectedOptions[0]?.dataset.sector
    if (category?.dataset.sector && sector && category.dataset.sector !== sector) {
      this.showFieldError(purchaser, `Selecione um comprador do setor ${category.dataset.sectorLabel}.`)
      valid = false
    }

    if (!valid) {
      this.focusFirstError()
    }
    return valid
  }

  showServerErrors(result) {
    const unplaced = []
    const showErrors = (errors, prefix) => {
      Object.entries(errors || {}).forEach(([attribute, messages]) => {
        // Nested errors are placed using the submitted row keys below.
        if (attribute.startsWith("invoice_numbers")) return
        const name = ["supplier", "purchaser", "budget_category", "cost_center"].includes(attribute) ? `${attribute}_id` : attribute
        const message = [].concat(messages).join(", ")
        if (!this.showFieldError(this.field(`${prefix}[${name}]`), message)) unplaced.push(message)
      })
    }
    showErrors(result.errors, "invoice")
    Object.entries(result.invoice_number_errors || {}).forEach(([key, errors]) => {
      showErrors(errors, `invoice[invoice_numbers_attributes][${key}]`)
    })
    if (unplaced.length) showFlash(unplaced.join(" "), { type: "danger" })
    this.focusFirstError()
  }

  async submit(event) {
    event.preventDefault()
    if (this.submitting || !this.validate()) return

    const data = new FormData(this.element)
    const buttons = [...this.element.querySelectorAll("[type='submit']")].filter((button) => !button.disabled)
    this.submitting = true
    this.element.setAttribute("aria-busy", "true")
    buttons.forEach((button) => { button.disabled = true })

    try {
      const response = await fetch(this.element.action, {
        method: this.element.method,
        body: data,
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        }
      })
      const result = await response.json()
      if (response.status === 422 && result.errors) {
        this.showServerErrors(result)
      } else if (response.ok && result.redirect_url) {
        Turbo.visit(result.redirect_url)
      } else {
        throw new Error("save failed")
      }
    } catch {
      showFlash("Não foi possível salvar a nota fiscal. Seus dados e anexos foram mantidos neste formulário. Tente novamente.", { type: "danger" })
    } finally {
      this.submitting = false
      this.element.removeAttribute("aria-busy")
      buttons.forEach((button) => { button.disabled = false })
    }
  }
}
