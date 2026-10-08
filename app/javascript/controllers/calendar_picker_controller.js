import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Navigation shares the calendar surfaces used by the task editor.
export default class extends Controller {
  static targets = ["button", "panel", "heading", "options"]
  static values = { mode: String, date: String }

  connect() {
    this.reposition = event => { if (event.target !== this.panelTarget) this.position() }
    window.addEventListener("resize", this.reposition)
    window.visualViewport?.addEventListener("resize", this.reposition)
    document.addEventListener("scroll", this.reposition, true)
  }

  disconnect() {
    this.cancelWaiting?.()
    this.close()
    window.removeEventListener("resize", this.reposition)
    window.visualViewport?.removeEventListener("resize", this.reposition)
    document.removeEventListener("scroll", this.reposition, true)
  }

  toggle() {
    if (!this.panelTarget.hidden) { this.close(); return }
    const selected = new Date(`${this.dateValue}T12:00:00`)
    this.calendar = new Date(selected.getFullYear(), selected.getMonth(), 1)
    this.render()
    this.panelTarget.hidden = false
    this.panelTarget.showPopover()
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.position()
    const focused = this.optionsTarget.querySelector('[aria-pressed="true"]') || this.optionsTarget.querySelector('button')
    focused?.focus({ preventScroll: true })
  }

  close() {
    if (this.panelTarget.matches(":popover-open")) this.panelTarget.hidePopover()
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
    this.cancel()
  }

  cancel() { this.close(); this.buttonTarget.focus() }

  changePeriod(event) {
    const offset = Number(event.currentTarget.dataset.offset)
    if (this.modeValue === "month") this.calendar.setFullYear(this.calendar.getFullYear() + offset)
    else this.calendar.setMonth(this.calendar.getMonth() + offset)
    this.render()
    this.position()
  }

  isoDate(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`
  }

  render() {
    const monthly = this.modeValue === "month"
    const year = this.calendar.getFullYear(), month = this.calendar.getMonth()
    this.headingTarget.textContent = monthly ? year : this.calendar.toLocaleDateString("pt-BR", { month: "long", year: "numeric" })
    this.optionsTarget.replaceChildren()
    if (!monthly) {
      for (let i = 0; i < this.calendar.getDay(); i++) this.optionsTarget.append(document.createElement("span"))
    }
    const count = monthly ? 12 : new Date(year, month + 1, 0).getDate()
    const today = this.isoDate(new Date())
    for (let i = 0; i < count; i++) {
      const date = monthly ? new Date(year, i, 1) : new Date(year, month, i + 1)
      const value = this.isoDate(date)
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.date = value
      button.textContent = monthly ? date.toLocaleDateString("pt-BR", { month: "short" }).replace(/\.$/, "") : i + 1
      button.setAttribute("aria-label", date.toLocaleDateString("pt-BR", monthly ? { month: "long", year: "numeric" } : { dateStyle: "full" }))
      button.setAttribute("aria-pressed", String(monthly ? value.slice(0, 7) === this.dateValue.slice(0, 7) : value === this.dateValue))
      if (monthly ? value.slice(0, 7) === today.slice(0, 7) : value === today) button.setAttribute("aria-current", "date")
      this.optionsTarget.append(button)
    }
  }

  choose(event) {
    const button = event.target.closest("button[data-date]")
    if (button) this.navigate(button.dataset.date)
  }

  today() { this.navigate(this.isoDate(new Date())) }

  async navigate(date) {
    this.close()
    const frame = this.element.closest(".time-off-page")?.querySelector("#time-off-calendar-content")
    // Finish an in-flight filter update before starting a full-page visit so
    // the frame's history update cannot replace the newly selected month.
    if (frame?.hasAttribute("busy")) await this.waitForFrame(frame)
    if (!this.element.isConnected) return
    const month = date.slice(0, 7), monthly = this.modeValue === "month"
    const url = new URL(window.location.href)
    // Filters can change within a Turbo frame while the header stays in place.
    const filters = this.element.closest(".time-off-page")?.querySelector(".time-off-calendar-filters")
    for (const key of ["role", "group", "name", "per_page", "calendar_period"]) {
      const field = filters?.elements.namedItem(key)
      if (field) url.searchParams.set(key, field.value)
    }
    url.searchParams.set("tab", monthly ? "calendar" : "day")
    url.searchParams.set("date", monthly ? `${month}-01` : date)
    url.searchParams.set("month", month)
    url.searchParams.set("page", "1")
    if (url.searchParams.get("calendar_period") !== "month" && (monthly || month !== this.dateValue.slice(0, 7))) {
      url.searchParams.set("calendar_period", monthly ? `${month}-01` : date)
    }
    Turbo.visit(url.href)
  }

  waitForFrame(frame) {
    return new Promise(resolve => {
      const finished = event => {
        if (event && event.target !== frame && event.target.closest?.(".time-off-page") !== this.element.closest(".time-off-page")) return
        frame.removeEventListener("turbo:frame-load", finished)
        frame.removeEventListener("turbo:frame-missing", finished)
        document.removeEventListener("turbo:fetch-request-error", finished)
        this.cancelWaiting = null
        // Turbo completes the frame's history visit after its load event.
        requestAnimationFrame(resolve)
      }
      frame.addEventListener("turbo:frame-load", finished)
      frame.addEventListener("turbo:frame-missing", finished)
      document.addEventListener("turbo:fetch-request-error", finished)
      this.cancelWaiting = () => finished()
    })
  }

  move(event) {
    const button = event.target.closest("button[data-date]")
    if (!button) return
    const columns = this.modeValue === "month" ? 3 : 7
    const offsets = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -columns, ArrowDown: columns }
    if (!(event.key in offsets)) return
    event.preventDefault()
    const buttons = [...this.optionsTarget.querySelectorAll("button")]
    buttons[buttons.indexOf(button) + offsets[event.key]]?.focus({ preventScroll: true })
  }

  position() {
    if (this.panelTarget.hidden) return
    const anchor = this.buttonTarget.getBoundingClientRect(), panel = this.panelTarget
    const viewport = window.visualViewport
    const width = viewport?.width || window.innerWidth, height = viewport?.height || window.innerHeight
    const top = viewport?.offsetTop || 0, left = viewport?.offsetLeft || 0, gap = 8
    panel.style.width = `${Math.min(320, width - 24)}px`
    panel.style.maxHeight = "none"
    const below = top + height - anchor.bottom - gap - 12, above = anchor.top - top - gap - 12
    const upwards = below < panel.offsetHeight && above > below
    panel.style.maxHeight = `${Math.max(120, upwards ? above : below)}px`
    panel.style.left = `${Math.max(left + 12, Math.min(anchor.left, left + width - panel.offsetWidth - 12))}px`
    panel.style.top = `${Math.max(top + 12, upwards ? anchor.top - panel.offsetHeight - gap : anchor.bottom + gap)}px`
  }
}
