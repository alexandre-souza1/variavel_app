import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = [
    "routeQuantity",
    "sourceList",
    "slot",
    "slotList",
    "plateInput",
    "destroyInput"
  ]

  connect() {
    this.sortables = []
    this.setupSortable()
    this.refreshSlots()
  }

  syncSlots() {
    this.refreshSlots()
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

    this.slotTargets.forEach((slot) => {
      const position = Number(slot.dataset.position)
      const slotIsActive = !Number.isInteger(position) || position < activeSlotCount
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
