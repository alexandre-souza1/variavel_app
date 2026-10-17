import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "option", "checkbox", "count", "clear", "empty", "trigger", "panel", "form", "status"]
  static values = { autosave: Boolean }

  connect() {
    if (this.hasCountTarget) this.updateCount()
    this.savedIds = this.selectedIds()
    this.saving = false
    this.pending = false
    if (this.hasPanelTarget) {
      this.reposition = this.position.bind(this)
      window.addEventListener("resize", this.reposition)
      document.addEventListener("scroll", this.reposition, true)
      window.visualViewport?.addEventListener("resize", this.reposition)
    }
  }

  disconnect() {
    cancelAnimationFrame(this.saveFrame)
    if (!this.hasPanelTarget) return
    this.hide()
    window.removeEventListener("resize", this.reposition)
    document.removeEventListener("scroll", this.reposition, true)
    window.visualViewport?.removeEventListener("resize", this.reposition)
  }

  updateCount() {
    const count = this.checkboxTargets.filter(input => input.checked).length
    this.countTarget.textContent = count === 0 ? "Nenhuma selecionada" : `${count} selecionada${count === 1 ? "" : "s"}`
    if (this.hasClearTarget) this.clearTarget.hidden = count === 0
  }

  filter() {
    const normalize = value => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-BR")
    const query = normalize(this.searchTarget.value.trim())
    this.optionTargets.forEach(option => { option.hidden = !normalize(option.dataset.labelName).includes(query) })
    this.emptyTarget.hidden = this.optionTargets.some(option => !option.hidden)
    this.position()
  }

  clear() {
    this.checkboxTargets.forEach(input => { input.checked = false })
    this.updateCount()
  }

  preventSubmit(event) { event.preventDefault() }

  selectedIds() {
    return this.checkboxTargets.filter(input => input.checked).map(input => input.value)
  }

  changed(event) {
    if (!this.checkboxTargets.includes(event.target)) return
    this.updateCount()
    this.pending = true
    this.save()
  }

  save() {
    if (!this.autosaveValue || this.saving || !this.pending) return
    this.saving = true
    this.pending = false
    this.submittedIds = this.selectedIds()
    this.statusTarget.textContent = "Salvando…"
    this.formTarget.requestSubmit()
  }

  submitting() {
    this.saving = true
  }

  submitted(event) {
    this.saving = false
    if (event.detail.success) {
      this.savedIds = this.submittedIds
      if (this.pending) this.saveFrame = requestAnimationFrame(() => this.save())
    } else {
      this.pending = false
      this.checkboxTargets.forEach(input => { input.checked = this.savedIds.includes(input.value) })
      this.updateCount()
      if (this.statusTarget.textContent === "Salvando…") {
        this.statusTarget.textContent = "Não foi possível salvar. Tente novamente."
      }
    }
    this.position()
  }

  toggle() {
    if (!this.panelTarget.hidden) return this.close()
    this.dispatch("opened")
    this.panelTarget.hidden = false
    this.panelTarget.showPopover()
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.position()
    this.searchTarget.focus({ preventScroll: true })
  }

  hide() {
    this.panelTarget.hidePopover()
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  close() {
    this.hide()
    this.triggerTarget.focus({ preventScroll: true })
  }

  outside(event) {
    if (!this.panelTarget.hidden && !this.panelTarget.contains(event.target) && !this.triggerTarget.contains(event.target)) this.hide()
  }

  escape(event) {
    if (this.panelTarget.hidden) return
    event.preventDefault()
    this.close()
  }

  otherOpened(event) {
    if (event.target !== this.element) this.hide()
  }

  position() {
    if (!this.hasPanelTarget || this.panelTarget.hidden) return
    const anchor = this.triggerTarget.getBoundingClientRect()
    const viewport = window.visualViewport
    const width = viewport?.width || window.innerWidth
    const height = viewport?.height || window.innerHeight
    const top = viewport?.offsetTop || 0
    const left = viewport?.offsetLeft || 0
    const gap = 8
    const below = top + height - anchor.bottom - gap - 12
    const above = anchor.top - top - gap - 12
    const upwards = below < 300 && above > below
    const panel = this.panelTarget
    panel.style.width = `${Math.min(320, width - 24)}px`
    panel.style.maxHeight = `${Math.max(120, Math.min(360, upwards ? above : below))}px`
    panel.style.left = `${Math.max(left + 12, Math.min(anchor.left, left + width - panel.offsetWidth - 12))}px`
    panel.style.top = `${Math.max(top + 12, upwards ? anchor.top - panel.offsetHeight - gap : anchor.bottom + gap)}px`
  }
};
