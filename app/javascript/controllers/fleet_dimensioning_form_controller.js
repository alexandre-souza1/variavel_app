import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = [
    "routeQuantity",
    "specialRouteQuantity",
    "specialRoutes",
    "specialRoute",
    "sourceList",
    "slot",
    "slotList",
    "plateInput",
    "destroyInput",
    "copyStatus"
  ]

  static values = { copyUrl: String }

  connect() {
    this.sortables = []
    this.setupSortable()
    this.refreshSlots()
  }

  syncSlots() {
    this.refreshSlots()
  }

  async copyPreviousMonth(event) {
    const button = event.currentTarget
    button.disabled = true
    this.showCopyStatus("Buscando o dimensionamento do mês anterior…")

    try {
      const url = new URL(this.copyUrlValue, window.location.origin)
      const form = new FormData(this.element)
      for (const field of ["period_year", "period_month", "period_half"]) {
        const name = `fleet_dimensioning[${field}]`
        url.searchParams.set(name, form.get(name) || "")
      }

      const response = await fetch(url, {
        headers: { Accept: "text/html" },
        credentials: "same-origin"
      })
      if (!response.ok) {
        const error = await response.json()
        this.showCopyStatus(error.error || "Não foi possível carregar o dimensionamento anterior.", true)
        return
      }

      const template = document.createElement("template")
      template.innerHTML = await response.text()
      const newForm = template.content.querySelector(".fleet-dimensioning-form")
      if (!newForm) throw new Error("Formulário não encontrado")
      this.element.replaceWith(newForm)
    } catch (_error) {
      this.showCopyStatus("Não foi possível carregar o dimensionamento anterior. Tente novamente.", true)
    } finally {
      button.disabled = false
    }
  }

  showCopyStatus(message, error = false) {
    this.copyStatusTarget.textContent = message
    this.copyStatusTarget.classList.remove("d-none")
    this.copyStatusTarget.classList.toggle("fleet-dimensioning-copy-status--error", error)
  }

  disconnect() {
    this.sortables.forEach((sortable) => sortable.destroy())
  }

  setupSortable() {
    const lists = [this.sourceListTarget, ...this.slotListTargets]

    lists.forEach((list) => {
      const sortable = Sortable.create(list, {
        group: "fleet-dimensioning-standard-plates",
        animation: 150,
        draggable: ".fleet-dimensioning-plate",
        forceFallback: true,
        fallbackOnBody: true,
        fallbackTolerance: 3,
        fallbackClass: "fleet-dimensioning-plate--fallback",
        ghostClass: "fleet-dimensioning-plate--ghost",
        onAdd: (event) => this.added(event),
        onRemove: () => this.refreshSlots(),
        onEnd: () => this.refreshSlots()
      })

      this.sortables.push(sortable)
    })
  }

  added(event) {
    if (event.to === this.sourceListTarget) return

    const existingPlate = Array
      .from(event.to.querySelectorAll(".fleet-dimensioning-plate"))
      .find((plate) => plate !== event.item)

    if (existingPlate) {
      this.sourceListTarget.appendChild(existingPlate)
    }
  }

  refreshSlots() {
    const activeSlotCount = this.activeSlotCount()
    const activeSpecialRoutes = new Set(
      this.specialRouteQuantityTargets
        .filter(input => Number(input.value) > 0)
        .map(input => input.dataset.specialRouteQuantity)
    )

    this.specialRoutesTarget.classList.toggle("d-none", activeSpecialRoutes.size === 0)
    this.specialRouteTargets.forEach(route => {
      route.classList.toggle("d-none", !activeSpecialRoutes.has(route.dataset.routeKey))
    })

    this.slotTargets.forEach((slot) => {
      const position = Number(slot.dataset.position)
      const isSpecialRouteSlot = Boolean(slot.dataset.specialRoute)
      const slotIsActive = isSpecialRouteSlot
        ? activeSpecialRoutes.has(slot.dataset.specialRoute)
        : position < activeSlotCount
      const slotList = slot.querySelector(
        "[data-fleet-dimensioning-form-target='slotList']"
      )
      const plate = slotList.querySelector(".fleet-dimensioning-plate")
      let placeholder = slotList.querySelector(".fleet-dimensioning-placeholder")
      const plateInput = slot.querySelector(
        "[data-fleet-dimensioning-form-target='plateInput']"
      )
      const destroyInput = slot.querySelector(
        "[data-fleet-dimensioning-form-target='destroyInput']"
      )

      slot.classList.toggle("d-none", !slotIsActive)

      if (!slotIsActive && plate) {
        this.sourceListTarget.appendChild(plate)
      }

      if (plateInput) {
        plateInput.value = slotIsActive && plate ? plate.dataset.plateId : ""
      }

      if (destroyInput) {
        destroyInput.value = slotIsActive && plate ? "0" : "1"
      }

      if (!placeholder) {
        placeholder = document.createElement("div")
        placeholder.className = "fleet-dimensioning-placeholder"
        placeholder.textContent = "Arraste uma placa"
        slotList.appendChild(placeholder)
      }

      if (placeholder) {
        placeholder.classList.toggle("d-none", Boolean(plate))
      }
    })
  }

  activeSlotCount() {
    const value = Number(this.routeQuantityTarget.value)

    if (Number.isInteger(value) && value >= 0) return value

    return this.slotTargets.length
  }
}
