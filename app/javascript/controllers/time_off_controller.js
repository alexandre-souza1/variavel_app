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
    this.fillMembershipCorrection()
    if (this.hasSettingsTarget) {
      this.settings = Offcanvas.getOrCreateInstance(this.settingsTarget)
      if (this.settingsOpenValue) this.settings.show()
      this.beforeCache = () => this.settings.hide()
      document.addEventListener("turbo:before-cache", this.beforeCache)
    }
    if (!this.editableValue) return
    this.listTargets.forEach(list => {
      this.sortables.push(Sortable.create(list, {
        group: { name: "time-off", put: (_to, _from, person) => list.dataset.status !== "pending" && (!list.dataset.role || person.dataset.role === list.dataset.role), pull: list.dataset.status !== "pending" }, draggable: '.time-off-person[data-movable="true"]', sort: false,
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
          if (status === event.item.dataset.status) return
          this.open(event.item, status)
        }
      }))
    })
  }

  openSettings() { this.settings?.show() }
  closeSettings() { this.settings?.hide() }

  syncCalendarContext(event) {
    const periodPicker = event.target.querySelector('.time-off-period-picker')
    if (!periodPicker) return
    const calendarPeriod = periodPicker.querySelector('button[aria-pressed="true"]').value
    const calendarPage = periodPicker.elements.namedItem("page").value
    const group = periodPicker.elements.namedItem("group").value
    const name = periodPicker.elements.namedItem("name").value
    const perPage = periodPicker.elements.namedItem("per_page").value
    const role = periodPicker.elements.namedItem("role").value
    const filters = this.element.querySelector('.time-off-calendar-filters')
    if (filters) {
      filters.elements.namedItem("calendar_period").value = calendarPeriod
      filters.elements.namedItem("group").value = group
      filters.elements.namedItem("per_page").value = perPage
      filters.elements.namedItem("role").value = role
      const nameInput = filters.elements.namedItem("name")
      if (document.activeElement !== nameInput && !this.searchTimer) nameInput.value = name
      filters.querySelectorAll('.time-off-role-picker button').forEach(button => {
        button.setAttribute('aria-pressed', String(button.dataset.role === role))
      })
      this.updateSearchClear(filters)
    }
    this.element.querySelectorAll('.time-off-tabs a, #time-off-calendar .time-off-panel-heading a, .group-assignment-dialog form, .time-off-correction-form').forEach(link => {
      const isForm = link.tagName === "FORM"
      const url = new URL(isForm ? link.action : link.href)
      if (!link.closest('.time-off-panel-heading')) {
        url.searchParams.set("calendar_period", calendarPeriod)
        url.searchParams.set("page", calendarPage)
      }
      url.searchParams.set("group", group)
      url.searchParams.set("name", name)
      url.searchParams.set("per_page", perPage)
      url.searchParams.set("role", role)
      if (isForm) link.action = url.href
      else link.href = url.href
    })
  }

  searchCalendar(event) {
    this.updateSearchClear(event.target.form)
    if (event.isComposing) return
    clearTimeout(this.searchTimer)
    this.searchTimer = setTimeout(() => {
      this.searchTimer = null
      if (event.target.form?.isConnected) event.target.form.requestSubmit()
    }, 350)
  }

  submitCalendarSearch(event) {
    event.preventDefault()
    if (event.isComposing) return
    clearTimeout(this.searchTimer)
    this.searchTimer = null
    event.currentTarget.form.requestSubmit()
  }

  clearCalendarSearch(event) {
    const form = event.currentTarget.form
    form.elements.namedItem('name').value = ''
    this.updateSearchClear(form)
    this.submitCalendarSearch(event)
    form.elements.namedItem('name').focus()
  }

  filterCalendarRole(event) {
    const form = event.currentTarget.form
    form.elements.namedItem('role').value = event.currentTarget.dataset.role
    this.submitCalendarSearch(event)
  }

  updateSearchClear(form) {
    const button = form.querySelector('.time-off-search-clear')
    if (button) button.hidden = !form.elements.namedItem('name').value
  }

  fillMembershipCorrection() {
    const form = this.element.querySelector('.time-off-correction-form')
    if (!form) return
    const option = form.elements.namedItem('membership[id]').selectedOptions[0]
    const values = {
      starts_on: option?.dataset.startsOn || '',
      group_code: option?.dataset.groupCode || '',
      fixed_weekday: option?.dataset.fixedWeekday || '',
      standard_operation: option?.dataset.standardOperation || '',
      expected_updated_at: option?.dataset.updatedAt || ''
    }
    Object.entries(values).forEach(([field, value]) => { form.elements.namedItem(`membership[${field}]`).value = value })
    const dateInput = form.elements.namedItem('membership[starts_on]')
    if (option?.dataset.endsOn) dateInput.max = option.dataset.endsOn
    else dateInput.max = dateInput.dataset.scheduleEnd || ''
    form.elements.namedItem('membership[group_code]').dispatchEvent(new Event('change', { bubbles: true }))
  }

  confirmMembershipDeletion(event) {
    const form = event.currentTarget.form
    if (!form.reportValidity()) { event.preventDefault(); return }
    const option = form.elements.namedItem('membership[id]').selectedOptions[0]
    if (!window.confirm(`Excluir esta vigência da escala?\n\n${option.textContent.trim()}\n\nOs outros vínculos mantêm suas datas. O histórico e as férias serão preservados.`)) event.preventDefault()
  }

  syncMonth(event) {
    if (event.target.value) event.target.form.elements.namedItem("month").value = event.target.value.slice(0, 7)
  }

  syncDate(event) {
    if (event.target.value) event.target.form.elements.namedItem("date").value = `${event.target.value}-01`
  }

  disconnect() {
    clearTimeout(this.searchTimer)
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
