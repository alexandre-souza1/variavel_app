import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, version: Number }
  static targets = ["panel", "editButton", "saveButton", "cancelButton", "status", "plateSelect", "slotSelect"]

  connect() {
    this.sortables = []
    this.active = true
    this.desktopPointer = window.matchMedia("(min-width: 901px) and (hover: hover) and (pointer: fine)")
    this.onPointerChange = () => this.syncDrag()
    this.desktopPointer.addEventListener("change", this.onPointerChange)
  }

  disconnect() {
    this.active = false
    this.desktopPointer.removeEventListener("change", this.onPointerChange)
    this.destroyDrag()
  }

  async start() {
    this.element.dataset.editing = "true"
    this.panelTarget.hidden = false
    this.editButtonTarget.hidden = true
    this.mapController.setMode("map")
    this.element.querySelector('[data-parking-map-target="search"]').value = ""
    this.mapController.search()
    this.element.querySelectorAll('[data-parking-map-target="mode"][data-mode="list"]').forEach(button => { button.disabled = true })
    await this.syncDrag()
  }

  destroyDrag() {
    this.sortables.forEach(sortable => sortable.destroy())
    this.sortables = []
    this.element.dataset.dragEnabled = "false"
  }

  async syncDrag() {
    if (!this.active || this.element.dataset.editing !== "true") return
    if (!this.desktopPointer.matches) { this.destroyDrag(); return }
    if (this.sortables.length || this.loadingSortable) return
    this.loadingSortable = true
    try {
      const { default: Sortable } = await import("sortablejs")
      if (!this.active || !this.desktopPointer.matches) return
      this.sortables = [...this.element.querySelectorAll(".parking-drop")].map(container => Sortable.create(container, {
        group: "parking-plates", animation: 150, handle: ".parking-drag", draggable: ".parking-vehicle",
        forceFallback: true, fallbackOnBody: false, fallbackTolerance: 4, ghostClass: "parking-ghost",
        onEnd: event => {
          if (event.from !== event.to) {
            const displaced = [...event.to.children].find(child => child !== event.item && child.classList.contains("parking-vehicle"))
            if (event.to.dataset.slot !== "pool" && displaced) event.from.append(displaced)
            this.changed()
          }
        }
      }))
      this.element.dataset.dragEnabled = "true"
    } catch {
      this.statusTarget.textContent = "O arraste está indisponível. Use os campos de placa e vaga abaixo."
    } finally { this.loadingSortable = false }
  }

  get mapController() { return this.application.getControllerForElementAndIdentifier(this.element, "parking-map") }

  assign() {
    const plate = this.plateSelectTarget.value
    const target = this.element.querySelector(`.parking-drop[data-slot="${this.slotSelectTarget.value}"]`)
    const card = [...this.element.querySelectorAll(".parking-vehicle")].find(item => item.dataset.plate === plate)
    if (!target || !card || card.parentElement === target) return
    const source = card.parentElement
    const displaced = target.dataset.slot === "pool" ? null : target.querySelector(".parking-vehicle")
    target.append(card)
    if (displaced) source.append(displaced)
    this.changed()
  }

  changed() {
    this.saveButtonTarget.disabled = false
    this.statusTarget.textContent = "Alterações ainda não publicadas. Salve para atualizar a visualização de todos."
    this.mapController.search()
  }

  cancel() { window.location.reload() }

  async save() {
    const assignments = {}
    this.element.querySelectorAll(".parking-space .parking-drop").forEach(slot => {
      assignments[slot.dataset.slot] = slot.querySelector(".parking-vehicle")?.dataset.plate || ""
    })
    this.saveButtonTarget.disabled = true
    this.cancelButtonTarget.disabled = true
    this.panelTarget.querySelectorAll("select, .parking-assign button").forEach(control => { control.disabled = true })
    this.sortables.forEach(sortable => sortable.option("disabled", true))
    this.statusTarget.textContent = "Salvando distribuição…"
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH", headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
        body: JSON.stringify({ assignments, lock_version: this.versionValue })
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Não foi possível salvar. Tente novamente.")
      window.location.reload()
    } catch (error) {
      this.statusTarget.textContent = error instanceof TypeError ? "Falha de conexão. Suas alterações continuam na tela; tente salvar novamente." : error.message
      this.saveButtonTarget.disabled = false
      this.cancelButtonTarget.disabled = false
      this.panelTarget.querySelectorAll("select, .parking-assign button").forEach(control => { control.disabled = false })
      this.sortables.forEach(sortable => sortable.option("disabled", false))
    }
  }
}
