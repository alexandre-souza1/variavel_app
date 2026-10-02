import { Controller } from "@hotwired/stimulus"
import { Offcanvas } from "bootstrap"
import Sortable from "sortablejs"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["list", "dialog", "form", "personName", "error", "submit", "settings"]
  static values = { editable: Boolean, settingsOpen: Boolean }

  connect() {
    this.sortables = []
    this.saving = false
    if (this.hasSettingsTarget) {
      this.settings = Offcanvas.getOrCreateInstance(this.settingsTarget)
      if (this.settingsOpenValue) this.settings.show()
      this.beforeCache = () => this.settings.hide()
      document.addEventListener("turbo:before-cache", this.beforeCache)
    }
    if (!this.editableValue) return
    this.listTargets.forEach(list => {
      this.sortables.push(Sortable.create(list, {
        group: { name: "time-off", put: list.dataset.status !== "pending", pull: list.dataset.status !== "pending" }, draggable: '.time-off-person[data-movable="true"]', sort: false,
        animation: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 150,
        forceFallback: true, fallbackOnBody: true, fallbackTolerance: 3,
        delay: 150, delayOnTouchOnly: true,
        ghostClass: "time-off-person--ghost", emptyInsertThreshold: 25,
        onEnd: event => {
          if (event.from === event.to) return
          const status = event.to.dataset.status
          // Restore immediately: only a successful save changes availability.
          const siblings = [...event.from.querySelectorAll(".time-off-person")]
          event.from.insertBefore(event.item, siblings[event.oldDraggableIndex] || event.from.querySelector(".time-off-list-empty"))
          this.open(event.item, status)
        }
      }))
    })
  }

  openSettings() { this.settings?.show() }
  closeSettings() { this.settings?.hide() }

  syncCalendarContext(event) {
    const calendarPeriod = event.target.querySelector('.time-off-period-picker button[aria-pressed="true"]').value
    const calendarPage = event.target.querySelector('.time-off-period-picker input[name="page"]').value
    const periodInput = this.element.querySelector('.time-off-filters input[name="calendar_period"]')
    if (periodInput) periodInput.value = calendarPeriod
    this.element.querySelectorAll('.time-off-tabs a, .time-off-group-legend a').forEach(link => {
      const url = new URL(link.href)
      url.searchParams.set("calendar_period", calendarPeriod)
      url.searchParams.set("page", calendarPage)
      link.href = url.href
    })
  }

  syncMonth(event) {
    if (event.target.value) event.target.form.elements.namedItem("month").value = event.target.value.slice(0, 7)
  }

  syncDate(event) {
    if (event.target.value) event.target.form.elements.namedItem("date").value = `${event.target.value}-01`
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.settings?.hide()

    this.sortables.forEach(sortable => sortable.destroy())
    this.abortController?.abort()
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  open(person, status = person.dataset.status) {
    if (this.saving || !this.editableValue) return
    this.formTarget.reset()
    this.field("membership_id").value = person.dataset.membershipId
    this.field("expected_revision").value = person.dataset.revision
    this.field("status").value = status
    this.personNameTarget.textContent = person.dataset.name
    this.errorTarget.textContent = ""
    this.dialogTarget.showModal()
    this.field("reason").focus()
  }

  cancel(event) {
    event?.preventDefault()
    if (!this.saving) this.dialogTarget.close()
  }

  field(name) {
    return this.formTarget.elements.namedItem(`change[${name}]`)
  }

  async save(event) {
    event.preventDefault()
    if (this.saving || !this.formTarget.reportValidity()) return
    this.saving = true
    this.submitTarget.disabled = true
    this.errorTarget.textContent = ""
    this.abortController = new AbortController()
    try {
      const response = await fetch(this.formTarget.action, {
        method: "PATCH", body: new FormData(this.formTarget), credentials: "same-origin",
        signal: this.abortController.signal,
        headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      })
      if (response.redirected) throw new Error("Sua sessão expirou. Atualize a página para entrar novamente.")
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Não foi possível salvar a alteração.")
      this.dialogTarget.close()
      Turbo.visit(window.location.href, { action: "replace" })
    } catch (error) {
      if (error.name !== "AbortError") this.errorTarget.textContent = error.message === "Failed to fetch" ? "Falha de conexão. A alteração não foi confirmada; tente novamente." : error.message
    } finally {
      this.saving = false
      this.submitTarget.disabled = false
    }
  }
}
