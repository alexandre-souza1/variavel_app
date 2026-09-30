import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["wrapper", "button", "buttonLabel", "title", "form", "tool", "panel", "date", "users", "recurrence", "reminder", "hint", "error", "submit"]

  connect() {
    this.open = false
    this.saving = false
    this.update()
  }

  disconnect() {
    cancelAnimationFrame(this.focusFrame)
  }

  toggle() {
    this.setOpen(!this.open)
    if (this.open) {
      this.dispatch("opened")
      this.focusFrame = requestAnimationFrame(() => this.titleTarget.focus())
    }
  }

  setOpen(open) {
    this.open = open
    this.element.classList.toggle("is-open", open)
    this.wrapperTarget.inert = !open
    this.buttonTarget.setAttribute("aria-expanded", String(open))
    this.buttonLabelTarget.textContent = open ? "Nova tarefa" : (this.hasDraft() ? "Continuar tarefa" : "Adicionar tarefa")
  }

  hasDraft() {
    return this.titleTarget.value.trim() || this.dateTarget.value || this.usersTarget.selectedOptions.length || this.recurrenceTarget.value || this.reminderTarget.checked
  }

  otherOpened(event) {
    if (event.target !== this.element && !this.saving) this.setOpen(false)
  }

  outside(event) {
    if (this.open && !this.saving && !this.element.contains(event.target)) this.setOpen(false)
  }

  escape(event) {
    if (this.saving) return
    event.preventDefault()
    this.setOpen(false)
    this.buttonTarget.focus()
  }

  showPanel(event) {
    const name = event.currentTarget.dataset.panel
    const panel = this.panelTargets.find(panel => panel.dataset.panel === name)
    this.activatePanel(panel.hidden ? name : null)
  }

  activatePanel(name) {
    this.panelTargets.forEach(panel => { panel.hidden = panel.dataset.panel !== name })
    this.toolTargets.forEach(tool => tool.setAttribute("aria-expanded", String(tool.dataset.panel === name)))
    if (name === "users") this.usersTarget.tomselect?.focus()
  }

  update() {
    const date = this.dateTarget.value
    const users = Array.from(this.usersTarget.selectedOptions)
    const recurrence = this.recurrenceTarget
    const summaries = {
      date: date ? date.split("-").reverse().slice(0, 2).join("/") : "Prazo",
      users: users.length ? `${users.length} ${users.length === 1 ? "responsável" : "responsáveis"}` : "Responsáveis",
      repeat: recurrence.value ? recurrence.selectedOptions[0].textContent : "Repetição"
    }
    this.toolTargets.forEach(tool => {
      tool.querySelector("[data-summary]").textContent = summaries[tool.dataset.panel]
      tool.classList.toggle("is-filled", Boolean({ date, users: users.length, repeat: recurrence.value }[tool.dataset.panel]))
    })
    this.dateTarget.required = Boolean(recurrence.value || this.reminderTarget.checked)
    this.hintTarget.hidden = !this.dateTarget.required || Boolean(date)
  }

  invalidDate() {
    this.activatePanel("date")
    this.dateTarget.focus()
  }

  submitting() {
    this.saving = true
    this.errorTarget.hidden = true
  }

  afterSubmit(event) {
    this.saving = false
    if (event.detail.success) this.cancel()
    else this.errorTarget.hidden = false
  }

  cancel() {
    if (this.saving) return
    this.formTarget.reset()
    this.usersTarget.tomselect?.clear(true)
    this.activatePanel(null)
    this.update()
    this.errorTarget.hidden = true
    this.setOpen(false)
    this.buttonTarget.focus()
  }
}
