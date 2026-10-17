import { Controller } from "@hotwired/stimulus"
import { showFlash } from "controllers/flash_controller"
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
    "copyButton",
    "profileSummary"
  ]

  connect() {
    this.sortables = []
    this.setupSortable()
    this.refreshSlots()
  }

  syncSlots() {
    this.refreshSlots()
  }

  async copyPreviousPeriod(event) {
    const button = event.currentTarget
    const originalContent = button.innerHTML
    const buttons = this.copyButtonTargets
    buttons.forEach(button => { button.disabled = true })
    button.textContent = "Buscando…"

    try {
      const url = new URL(event.params.url, window.location.origin)
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
        showFlash(error.error || "Não foi possível carregar o dimensionamento anterior.", { type: "warning" })
        return
      }

      const template = document.createElement("template")
      template.innerHTML = await response.text()
      const newForm = template.content.querySelector(".fleet-dimensioning-form")
      if (!newForm) throw new Error("Formulário não encontrado")
      this.element.replaceWith(newForm)
      showFlash(`Placas e quantidades carregadas de ${newForm.dataset.copiedDimensioningLabel}. Revise antes de salvar.`)
    } catch (_error) {
      showFlash("Não foi possível carregar o dimensionamento anterior. Tente novamente.", { type: "warning" })
    } finally {
      button.innerHTML = originalContent
      buttons.forEach(button => { button.disabled = false })
    }
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

    this.refreshProfileSummary()
  }

  refreshProfileSummary() {
    const counts = new Map()
    let total = 0

    this.slotTargets.forEach(slot => {
      if (slot.classList.contains("d-none")) return

      const plate = slot.querySelector(".fleet-dimensioning-plate")
      if (!plate) return

      const profile = plate.dataset.plateProfile || "Sem perfil"
      counts.set(profile, (counts.get(profile) || 0) + 1)
      total += 1
    })

    const badges = [...counts.entries()]
      .sort(([a], [b]) => a.localeCompare(b, "pt-BR"))
      .map(([profile, count]) => {
        const badge = document.createElement("span")
        badge.className = "fleet-dimensioning-profile-summary__item"
        badge.textContent = `${profile}: ${count}`
        return badge
      })
    const totalBadge = document.createElement("strong")
    totalBadge.className = "fleet-dimensioning-profile-summary__item"
    totalBadge.textContent = `Total: ${total}`
    this.profileSummaryTarget.replaceChildren(...badges, totalBadge)
  }

  activeSlotCount() {
    const value = Number(this.routeQuantityTarget.value)

    if (Number.isInteger(value) && value >= 0) return value

    return this.slotTargets.length
  }
};
