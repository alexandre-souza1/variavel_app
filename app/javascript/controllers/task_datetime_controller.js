import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["value", "button", "display", "panel", "month", "days", "hours", "minutes", "error"]

  connect() {
    this.refresh()
    this.reposition = this.position.bind(this)
    window.addEventListener("resize", this.reposition)
    window.visualViewport?.addEventListener("resize", this.reposition)
    document.addEventListener("scroll", this.reposition, true)
    this.modal = this.element.closest(".modal")
    this.onModalHide = () => this.close()
    this.modal?.addEventListener("hide.bs.modal", this.onModalHide)
  }

  disconnect() {
    this.panelTarget.hidePopover()
    window.removeEventListener("resize", this.reposition)
    window.visualViewport?.removeEventListener("resize", this.reposition)
    document.removeEventListener("scroll", this.reposition, true)
    this.modal?.removeEventListener("hide.bs.modal", this.onModalHide)
  }

  refresh() {
    const value = this.valueTarget.value
    const [date, time] = value.split("T")
    this.displayTarget.textContent = date ? `${date.split("-").reverse().join("/")} ${time.slice(0, 5)}` : "Escolher data e hora"
    this.buttonTarget.classList.toggle("is-filled", Boolean(value))
  }

  toggle() {
    if (this.buttonTarget.getAttribute("aria-expanded") === "true") { this.close(); return }
    const [date, time = "00:00"] = this.valueTarget.value.split("T")
    this.draft = date || ""
    const selected = date ? new Date(`${date}T12:00:00`) : new Date()
    this.calendar = new Date(selected.getFullYear(), selected.getMonth(), 1)
    const [hours, minutes] = time.split(":")
    this.hoursTarget.value = hours
    this.minutesTarget.value = minutes.slice(0, 2)
    this.errorTarget.hidden = true
    this.renderCalendar()
    this.panelTarget.hidden = false
    this.panelTarget.showPopover()
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.position()
    this.daysTarget.querySelector('[aria-pressed="true"], button')?.focus({ preventScroll: true })
  }

  close() {
    this.panelTarget.hidePopover()
    this.panelTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
  }

  outside(event) {
    if (!event.composedPath().includes(this.element)) this.close()
  }

  escape(event) {
    if (this.panelTarget.hidden) return
    event.preventDefault()
    event.stopPropagation()
    this.close()
    this.buttonTarget.focus()
  }

  stop(event) { event.stopPropagation() }

  changeMonth(event) {
    this.calendar.setMonth(this.calendar.getMonth() + Number(event.currentTarget.dataset.offset))
    this.renderCalendar()
    this.position()
  }

  dateValue(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`
  }

  renderCalendar() {
    this.monthTarget.textContent = this.calendar.toLocaleDateString("pt-BR", { month: "long", year: "numeric" })
    this.daysTarget.replaceChildren()
    const year = this.calendar.getFullYear(), month = this.calendar.getMonth()
    for (let i = 0; i < this.calendar.getDay(); i++) this.daysTarget.append(document.createElement("span"))
    for (let day = 1; day <= new Date(year, month + 1, 0).getDate(); day++) {
      const date = new Date(year, month, day)
      const value = this.dateValue(date)
      const button = document.createElement("button")
      button.type = "button"
      button.textContent = day
      button.dataset.date = value
      button.setAttribute("aria-label", date.toLocaleDateString("pt-BR", { dateStyle: "full" }))
      button.setAttribute("aria-pressed", String(value === this.draft))
      if (value === this.dateValue(new Date())) button.setAttribute("aria-current", "date")
      this.daysTarget.append(button)
    }
  }

  choose(event) {
    const button = event.target.closest("button[data-date]")
    if (!button) return
    this.draft = button.dataset.date
    this.renderCalendar()
    this.hoursTarget.focus()
    this.hoursTarget.select()
  }

  today() {
    const date = new Date()
    this.draft = this.dateValue(date)
    this.calendar = new Date(date.getFullYear(), date.getMonth(), 1)
    this.renderCalendar()
  }

  apply(event) {
    event.preventDefault()
    event.stopPropagation()
    const hours = this.hoursTarget.value.trim(), minutes = this.minutesTarget.value.trim()
    if (!this.draft || !/^\d{1,2}$/.test(hours) || !/^\d{1,2}$/.test(minutes) || Number(hours) > 23 || Number(minutes) > 59) {
      this.errorTarget.hidden = false
      return
    }
    this.save(`${this.draft}T${hours.padStart(2, "0")}:${minutes.padStart(2, "0")}`)
  }

  clear() { this.save("") }

  save(value) {
    const changed = this.valueTarget.value !== value
    this.valueTarget.value = value
    this.refresh()
    this.close()
    this.buttonTarget.focus()
    if (changed) this.valueTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  position() {
    if (this.panelTarget.hidden) return
    const anchor = this.buttonTarget.getBoundingClientRect()
    const viewport = window.visualViewport
    const width = viewport?.width || window.innerWidth, height = viewport?.height || window.innerHeight, gap = 8
    const offsetTop = viewport?.offsetTop || 0, offsetLeft = viewport?.offsetLeft || 0
    const below = height + offsetTop - anchor.bottom - 12 - gap, above = anchor.top - offsetTop - 12 - gap
    const upwards = below < 380 && above > below
    const panel = this.panelTarget
    panel.style.width = `${Math.min(320, width - 24)}px`
    panel.style.maxHeight = `${Math.max(120, upwards ? above : below)}px`
    panel.style.left = `${Math.max(offsetLeft + 12, Math.min(anchor.left, offsetLeft + width - panel.offsetWidth - 12))}px`
    panel.style.top = `${Math.max(offsetTop + 12, upwards ? anchor.top - panel.offsetHeight - gap : anchor.bottom + gap)}px`
  }
}
