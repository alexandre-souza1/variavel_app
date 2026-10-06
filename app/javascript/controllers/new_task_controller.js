import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["wrapper", "button", "buttonLabel", "title", "form", "tool", "panel", "date", "calendarMonth", "calendarDays", "assignee", "userOption", "userSearch", "userCount", "noUsers", "badge", "labelOption", "labelSearch", "labelCount", "noLabels", "recurrence", "reminder", "reminderButton", "hint", "error", "submit"]

  connect() {
    this.open = false
    this.saving = false
    this.update()
    this.filterUsers()
    this.filterLabels()
    this.repositionPopover = this.positionPopover.bind(this)
    window.addEventListener("resize", this.repositionPopover)
    document.addEventListener("scroll", this.repositionPopover, true)
    window.visualViewport?.addEventListener("resize", this.repositionPopover)
  }

  disconnect() {
    cancelAnimationFrame(this.focusFrame)
    window.removeEventListener("resize", this.repositionPopover)
    document.removeEventListener("scroll", this.repositionPopover, true)
    window.visualViewport?.removeEventListener("resize", this.repositionPopover)
    this.panelTargets.filter(panel => panel.hasAttribute("popover")).forEach(panel => panel.hidePopover())
  }

  toggle() {
    this.setOpen(!this.open)
    if (this.open) {
      this.dispatch("opened")
      this.focusFrame = requestAnimationFrame(() => this.titleTarget.focus())
    }
  }

  setOpen(open) {
    if (!open) this.activatePanel(null)
    this.open = open
    this.element.classList.toggle("is-open", open)
    this.wrapperTarget.inert = !open
    this.buttonTarget.setAttribute("aria-expanded", String(open))
    this.buttonLabelTarget.textContent = open ? "Nova tarefa" : (this.hasDraft() ? "Continuar tarefa" : "Adicionar tarefa")
  }

  hasDraft() {
    return this.titleTarget.value.trim() || this.dateTarget.value || this.assigneeTargets.some(input => input.checked) || this.badgeTargets.some(input => input.checked) || this.recurrenceTarget.value || this.reminderTarget.checked
  }

  otherOpened(event) {
    if (event.target !== this.element && !this.saving) this.setOpen(false)
  }

  outside(event) {
    const floating = this.panelTargets.find(panel => panel.hasAttribute("popover") && !panel.hidden)
    if (floating && !floating.contains(event.target) && !this.toolTargets.find(tool => tool.dataset.panel === floating.dataset.panel).contains(event.target)) {
      this.activatePanel(null)
    }
    if (this.open && !this.saving && !this.element.contains(event.target)) this.setOpen(false)
  }

  escape(event) {
    if (this.saving) return
    event.preventDefault()
    const floating = this.panelTargets.find(panel => panel.hasAttribute("popover") && !panel.hidden)
    if (floating) {
      const button = this.toolTargets.find(tool => tool.dataset.panel === floating.dataset.panel)
      this.activatePanel(null)
      button.focus()
      return
    }
    this.setOpen(false)
    this.buttonTarget.focus()
  }

  showPanel(event) {
    const name = event.currentTarget.dataset.panel
    const panel = this.panelTargets.find(panel => panel.dataset.panel === name)
    this.activatePanel(panel.hidden ? name : null)
  }

  activatePanel(name) {
    this.panelTargets.filter(panel => panel.hasAttribute("popover") && panel.dataset.panel !== name).forEach(panel => panel.hidePopover())
    this.panelTargets.forEach(panel => { panel.hidden = panel.dataset.panel !== name })
    this.toolTargets.forEach(tool => tool.setAttribute("aria-expanded", String(tool.dataset.panel === name)))
    if (name === "users") {
      this.usersPanel.showPopover()
      this.positionPopover()
      this.userSearchTarget.focus({ preventScroll: true })
    }
    if (name === "labels") {
      this.panelTargets.find(panel => panel.dataset.panel === "labels").showPopover()
      this.positionPopover()
      this.labelSearchTarget.focus({ preventScroll: true })
    }
    if (name === "date") {
      const selected = this.dateTarget.value ? new Date(`${this.dateTarget.value}T12:00:00`) : new Date()
      this.calendarDate = new Date(selected.getFullYear(), selected.getMonth(), 1)
      this.renderCalendar()
      this.panelTargets.find(panel => panel.dataset.panel === "date").showPopover()
      this.positionPopover()
      this.calendarDaysTarget.querySelector('[aria-pressed="true"], button')?.focus({ preventScroll: true })
    }
  }

  get usersPanel() {
    return this.panelTargets.find(panel => panel.dataset.panel === "users")
  }

  get usersButton() {
    return this.toolTargets.find(tool => tool.dataset.panel === "users")
  }

  positionPopover() {
    const panel = this.panelTargets.find(panel => panel.hasAttribute("popover") && !panel.hidden)
    if (!panel) return
    const anchor = this.toolTargets.find(tool => tool.dataset.panel === panel.dataset.panel).getBoundingClientRect()
    const viewport = window.visualViewport
    const width = viewport?.width || window.innerWidth
    const height = viewport?.height || window.innerHeight
    const offsetTop = viewport?.offsetTop || 0
    const offsetLeft = viewport?.offsetLeft || 0
    const gap = 8
    const below = height + offsetTop - anchor.bottom - 12 - gap
    const above = anchor.top - offsetTop - 12 - gap
    const upwards = below < 300 && above > below
    panel.style.width = `${Math.min(320, width - 24)}px`
    panel.style.maxHeight = `${Math.max(120, Math.min(360, upwards ? above : below))}px`
    panel.style.left = `${Math.max(offsetLeft + 12, Math.min(anchor.left, offsetLeft + width - panel.offsetWidth - 12))}px`
    panel.style.top = `${Math.max(offsetTop + 12, upwards ? anchor.top - panel.offsetHeight - gap : anchor.bottom + gap)}px`
  }

  filterUsers() {
    const normalize = value => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-BR")
    const query = normalize(this.userSearchTarget.value.trim())
    this.userOptionTargets.forEach(option => { option.hidden = !normalize(option.dataset.name).includes(query) })
    this.noUsersTarget.hidden = this.userOptionTargets.some(option => !option.hidden)
    this.positionPopover()
  }

  preventSearchSubmit(event) {
    event.preventDefault()
  }

  filterLabels() {
    const normalize = value => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-BR")
    const query = normalize(this.labelSearchTarget.value.trim())
    this.labelOptionTargets.forEach(option => { option.hidden = !normalize(option.dataset.name).includes(query) })
    this.noLabelsTarget.hidden = this.labelOptionTargets.some(option => !option.hidden)
    this.positionPopover()
  }

  closeLabels() {
    this.activatePanel(null)
    this.toolTargets.find(tool => tool.dataset.panel === "labels").focus()
  }

  toggleReminder() {
    this.reminderTarget.checked = !this.reminderTarget.checked
    this.update()
  }

  closeUsers() {
    this.activatePanel(null)
    this.toolTargets.find(tool => tool.dataset.panel === "users").focus()
  }

  update() {
    const date = this.dateTarget.value
    const users = this.assigneeTargets.filter(input => input.checked)
    this.userCountTarget.textContent = users.length ? `${users.length} selecionado${users.length === 1 ? "" : "s"}` : "Nenhum selecionado"
    const recurrence = this.recurrenceTarget
    const labels = this.badgeTargets.filter(input => input.checked)
    this.labelCountTarget.textContent = labels.length ? `${labels.length} selecionada${labels.length === 1 ? "" : "s"}` : "Nenhuma selecionada"
    const summaries = {
      date: date ? date.split("-").reverse().slice(0, 2).join("/") : "Prazo",
      users: users.length ? `${users.length} ${users.length === 1 ? "responsável" : "responsáveis"}` : "Responsáveis",
      repeat: recurrence.value ? recurrence.selectedOptions[0].textContent : "Repetição",
      labels: labels.length ? String(labels.length) : "Etiquetas"
    }
    this.toolTargets.forEach(tool => {
      tool.querySelector("[data-summary]").textContent = summaries[tool.dataset.panel]
      tool.classList.toggle("is-filled", Boolean({ date, users: users.length, repeat: recurrence.value, labels: labels.length }[tool.dataset.panel]))
      if (tool.dataset.panel === "labels") tool.setAttribute("aria-label", `Selecionar etiquetas: ${labels.length} selecionada${labels.length === 1 ? "" : "s"}`)
    })
    this.dateTarget.required = Boolean(recurrence.value || this.reminderTarget.checked)
    this.hintTarget.hidden = !this.dateTarget.required || Boolean(date)
    this.reminderButtonTarget.setAttribute("aria-pressed", String(this.reminderTarget.checked))
    this.reminderButtonTarget.querySelector("i").classList.toggle("bi-bell-fill", this.reminderTarget.checked)
    this.reminderButtonTarget.querySelector("i").classList.toggle("bi-bell", !this.reminderTarget.checked)
  }

  validate(event) {
    if ((this.recurrenceTarget.value || this.reminderTarget.checked) && !this.dateTarget.value) {
      event.preventDefault()
      event.stopImmediatePropagation()
      this.activatePanel("date")
    }
  }

  changeMonth(event) {
    this.calendarDate.setMonth(this.calendarDate.getMonth() + Number(event.currentTarget.dataset.offset))
    this.renderCalendar()
    this.positionPopover()
  }

  dateValue(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`
  }

  renderCalendar() {
    const year = this.calendarDate.getFullYear()
    const month = this.calendarDate.getMonth()
    this.calendarMonthTarget.textContent = this.calendarDate.toLocaleDateString("pt-BR", { month: "long", year: "numeric" })
    this.calendarDaysTarget.replaceChildren()
    for (let i = 0; i < this.calendarDate.getDay(); i++) this.calendarDaysTarget.append(document.createElement("span"))
    for (let day = 1; day <= new Date(year, month + 1, 0).getDate(); day++) {
      const date = new Date(year, month, day)
      const value = this.dateValue(date)
      const button = document.createElement("button")
      button.type = "button"
      button.textContent = day
      button.dataset.date = value
      button.setAttribute("aria-label", date.toLocaleDateString("pt-BR", { dateStyle: "full" }))
      button.setAttribute("aria-pressed", String(value === this.dateTarget.value))
      if (value === this.dateValue(new Date())) button.setAttribute("aria-current", "date")
      this.calendarDaysTarget.append(button)
    }
  }

  chooseDate(event) {
    const button = event.target.closest("button[data-date]")
    if (button) this.setDate(button.dataset.date)
  }

  today() { this.setDate(this.dateValue(new Date())) }

  clearDate() { this.setDate("") }

  setDate(value) {
    this.dateTarget.value = value
    this.update()
    this.activatePanel(null)
    this.toolTargets.find(tool => tool.dataset.panel === "date").focus()
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
    this.dateTarget.value = ""
    this.filterUsers()
    this.filterLabels()
    this.activatePanel(null)
    this.update()
    this.errorTarget.hidden = true
    this.setOpen(false)
    this.buttonTarget.focus()
  }
}
