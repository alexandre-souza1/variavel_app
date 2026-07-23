import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import * as bootstrap from "bootstrap"

export default class extends Controller {

  connect() {
    this.sortables = []
    this.pendingEvent = null
    this.modalConfirmed = false
    this.editable = this.element.dataset.editable === "true"
    this.isTouchDevice = window.matchMedia("(pointer: coarse)").matches

    if (!this.editable) return

    this.element.querySelectorAll(".sortable-list").forEach((list) => {

      const sortable = Sortable.create(list, {

        group: "fleet",

        animation: 150,

        sort: list.id !== "available-list",

        delay: this.isTouchDevice ? 180 : 0,

        delayOnTouchOnly: true,

        touchStartThreshold: 5,

        fallbackTolerance: 5,

        fallbackOnBody: true,

        scroll: true,

        bubbleScroll: true,

        scrollSensitivity: 90,

        scrollSpeed: 16,

        draggable: ".sortable-item",

        ghostClass: "fleet-plate-item--ghost",

        onEnd: (event) => {
          this.moved(event)
        }

      })


      this.sortables.push(sortable)

    })


    this.setupModal()
    this.setupObservationModal()

  }


  moved(event) {
    if (!this.editable) return

    const itemId = event.item.id.replace(
      "fleet_availability_item_",
      ""
    )


    const statusMap = {
      "available-list": "available",
      "exchange-list": "exchange",
      "unavailable-list": "unavailable"
    }


    const specialRoute = event.to.dataset.specialRoute
    const status = specialRoute ? "special_route" : statusMap[event.to.id]

    if (!status) return

    if (status === "available" && this.availableListIsFull(event.to)) {
      this.restoreItem(event)
      this.showAlert(
        "Não é possível adicionar outra placa: a disponibilidade já atingiu o limite pactuado."
      )
      return
    }

    if (status === "special_route" && this.specialRouteListIsFull(event.to)) {
      this.restoreItem(event)
      this.showAlert("Essa rota especial já atingiu a quantidade dimensionada.")
      return
    }

    if (specialRoute === "van" && event.item.dataset.vanPlate !== "true") {
      this.restoreItem(event)
      this.showAlert("A rota Van só pode ser roteirizada com uma placa VAN.")
      return
    }


    if (status === "unavailable") {

      this.pendingEvent = event

      this.openModal()

      return
    }

    this.adjustAvailableSlots(event)

    this.updateItem(
      itemId,
      status,
      this.itemPosition(event),
      null,
      null,
      event.item,
      specialRoute
    )

  }


  openModal() {
    const modalElement = document.getElementById("unavailableModal")
    this.modal = bootstrap.Modal.getOrCreateInstance(modalElement)

    // Resetar os campos para valores padrão
    document.getElementById("unavailableReason").value = "maintenance"
    document.getElementById("unavailableObservation").value =
      this.pendingEvent?.item?.dataset?.observation || ""

    this.modal.show()
  }


  setupModal() {

    const button = document.getElementById(
      "confirmUnavailable"
    )


    if (!button) return


    this.modalElement = document.getElementById(
      "unavailableModal"
    )


    this.modalElement.addEventListener("hidden.bs.modal", () => {

      if (this.pendingEvent && !this.modalConfirmed) {
        this.restoreItem(this.pendingEvent)
        this.pendingEvent = null
      }

      this.modalConfirmed = false

    })


    button.addEventListener("click", () => {


      if (!this.pendingEvent) return


      const event = this.pendingEvent


      const itemId = event.item.id.replace(
        "fleet_availability_item_",
        ""
      )


      const reason = document.getElementById(
        "unavailableReason"
      ).value


      const observation = document.getElementById(
        "unavailableObservation"
      ).value


      this.modalConfirmed = true

      this.adjustAvailableSlots(event)

      this.updateItem(
        itemId,
        "unavailable",
        this.itemPosition(event),
        reason,
        observation,
        event.item
      )


      bootstrap.Modal
        .getInstance(
          document.getElementById("unavailableModal")
        )
        .hide()


      this.pendingEvent = null

    })

  }


  setupObservationModal() {
    this.observationModalElement = document.getElementById("plateObservationModal")
    this.observationInput = document.getElementById("plateObservationText")
    this.observationButton = document.getElementById("confirmPlateObservation")

    if (!this.observationModalElement || !this.observationInput || !this.observationButton) return

    this.element.addEventListener("click", (event) => {
      const button = event.target.closest("[data-observation-edit]")

      if (!button) return

      this.pendingObservationItem = button.closest(".sortable-item")

      if (!this.pendingObservationItem) return

      this.observationInput.value = this.pendingObservationItem.dataset.observation || ""
      this.observationModal = bootstrap.Modal.getOrCreateInstance(
        this.observationModalElement
      )
      this.observationModal.show()
    })

    this.observationButton.addEventListener("click", () => {
      if (!this.pendingObservationItem) return

      const itemElement = this.pendingObservationItem
      const itemId = itemElement.id.replace(
        "fleet_availability_item_",
        ""
      )
      const list = itemElement.closest(".sortable-list")
      const specialRoute = list?.dataset.specialRoute || null
      const status = specialRoute ? "special_route" : itemElement.dataset.status
      const reason = status === "unavailable"
        ? itemElement.dataset.reason || "other"
        : null

      this.updateItem(
        itemId,
        status,
        this.itemPositionFromElement(itemElement),
        reason,
        this.observationInput.value,
        itemElement,
        specialRoute
      )

      this.observationModal.hide()
      this.pendingObservationItem = null
    })
  }


  async updateItem(
    itemId,
    status,
    position,
    reason = null,
    observation = null,
    itemElement = null,
    specialRoute = null
  ) {


    const response = await fetch(
      `/fleet_availabilities/${this.element.dataset.availabilityId}/fleet_availability_items/${itemId}`,
      {

        method: "PATCH",


        headers: {

          "Content-Type": "application/json",

          "X-CSRF-Token": document
            .querySelector("[name='csrf-token']")
            .content

        },


        body: JSON.stringify({

          fleet_availability_item: {

            status: status,

            position: position,

            reason: reason,

            observation: observation,

            special_route: specialRoute

          }

        })

      }

    )


    if (!response.ok) {
      window.location.reload()
      return
    }


    const item = await response.json()

    if (itemElement) {
      this.refreshItem(itemElement, item)
    }

    this.refreshBoard()

  }


  availableListIsFull(list) {
    const maxItems = Number(list.dataset.maxItems)

    if (!Number.isFinite(maxItems)) return false

    return list.querySelectorAll(".sortable-item").length > maxItems
  }


  specialRouteListIsFull(list) {
    const maxItems = Number(list.dataset.maxItems)

    if (!Number.isFinite(maxItems)) return false

    return list.querySelectorAll(".sortable-item").length > maxItems
  }


  itemPosition(event) {
    return Array.from(event.to.children).indexOf(event.item)
  }


  restoreItem(event) {
    const referenceNode = event.from.children[event.oldIndex] || null

    event.from.insertBefore(event.item, referenceNode)

    this.refreshBoard()
  }


  showAlert(message) {
    const alert = this.element.querySelector("[data-limit-alert]")

    if (!alert) return

    const messageElement = alert.querySelector("[data-limit-alert-message]")

    if (messageElement) {
      messageElement.textContent = message
    }

    alert.classList.remove("d-none")
    alert.classList.remove("fleet-limit-alert--visible")

    window.clearTimeout(this.limitAlertTimeout)

    requestAnimationFrame(() => {
      alert.classList.add("fleet-limit-alert--visible")
    })

    this.limitAlertTimeout = window.setTimeout(() => {
      alert.classList.remove("fleet-limit-alert--visible")

      window.setTimeout(() => {
        alert.classList.add("d-none")
      }, 180)
    }, 3600)
  }


  refreshItem(itemElement, item) {
    itemElement.dataset.status = item.status
    itemElement.dataset.reason = item.reason || ""
    itemElement.dataset.observation = item.observation || ""
    itemElement.classList.remove(
      "fleet-plate-item--availability",
      "fleet-plate-item--deposit",
      "fleet-plate-item--unavailable",
      "fleet-plate-item--special_route",
      "fleet-plate-item--default"
    )

    if (item.status === "available") {
      itemElement.classList.add("fleet-plate-item--availability")
      itemElement.removeAttribute("title")
      this.setAvailabilityDetails(itemElement)
    } else if (item.status === "exchange") {
      itemElement.classList.add("fleet-plate-item--deposit")
      itemElement.removeAttribute("title")
      this.setDepositDetails(itemElement)
    } else if (item.status === "unavailable") {
      itemElement.classList.add("fleet-plate-item--unavailable")
      itemElement.title = item.observation
        ? `${item.reason_label} - ${item.observation}`
        : item.reason_label
      this.setUnavailableDetails(itemElement, item)
    } else if (item.status === "special_route") {
      itemElement.classList.add("fleet-plate-item--special_route")
      itemElement.removeAttribute("title")
      this.setSpecialRouteDetails(itemElement)
    }

    this.setObservationDetails(itemElement, item.observation)
  }


  setAvailabilityDetails(itemElement) {
    const container = this.detailsContainer(itemElement, "fleet-plate-card__side")
    const position = this.itemIndex(itemElement)
    const standardPlate = this.standardPlateForPosition(position)

    container.innerHTML = `
      <span>
        Placa padrão: ${this.escapeHtml(standardPlate || "não definida")}
      </span>
    `
  }


  setDepositDetails(itemElement) {
    const container = this.detailsContainer(itemElement, "fleet-plate-card__side")

    container.innerHTML = ""
  }


  setUnavailableDetails(itemElement, item) {
    const container = this.detailsContainer(itemElement, "fleet-plate-card__defect-wrapper")

    container.innerHTML = `
      <div class="fleet-plate-card__defect" data-defect>
        <strong>${this.escapeHtml(item.reason_label)}</strong>
      </div>
    `
  }


  setSpecialRouteDetails(itemElement) {
    const container = this.detailsContainer(itemElement, "fleet-plate-card__side")

    container.innerHTML = ""
  }


  detailsContainer(itemElement, className = "") {
    let container = itemElement.querySelector("[data-live-details]")

    if (!container) {
      container = document.createElement("div")
      container.dataset.liveDetails = ""
      itemElement.querySelector(".fleet-plate-card").appendChild(container)
    }

    container.className = className

    return container
  }


  plateSetor(itemElement) {
    return itemElement.dataset.setor || "-"
  }


  itemIndex(itemElement) {
    const list = itemElement.closest(".sortable-list")

    if (!list) return 0

    return Array.from(list.children).indexOf(itemElement)
  }


  itemPositionFromElement(itemElement) {
    const list = itemElement.closest(".sortable-list")

    if (!list) return 0

    return Array.from(list.children).indexOf(itemElement)
  }


  setObservationDetails(itemElement, observation) {
    const container = itemElement.querySelector("[data-observation-display]")

    if (!container) return

    const button = container.querySelector("[data-observation-edit]")
    const observationText = String(observation || "").trim()
    const label = observationText
      ? `<span>${this.escapeHtml(observationText)}</span>`
      : "<span>Sem observação</span>"

    container.classList.toggle(
      "fleet-plate-card__observation--empty",
      !observationText
    )
    container.innerHTML = label

    if (button) {
      container.appendChild(button)
    }
  }


  standardPlateForPosition(position) {
    const availableList = document.getElementById("available-list")

    if (!availableList) return null

    try {
      const standardPlates = JSON.parse(availableList.dataset.standardPlates || "{}")

      return standardPlates[String(position)] || null
    } catch (_error) {
      return null
    }
  }


  refreshBoard() {
    this.refreshAvailabilityRows()
    this.refreshUnavailableRows()
    this.refreshEmptySlots()
    this.refreshSpecialRoutePlaceholders()
    this.refreshCounts()
    this.refreshCoverage()
    this.refreshMaintenance()
    this.refreshUsedProfiles()
  }


  refreshAvailabilityRows() {
    const availableList = document.getElementById("available-list")

    availableList
      .querySelectorAll(":scope > .sortable-item")
      .forEach((item) => {
        const index = this.itemIndex(item)
        const label = item.querySelector("[data-line-label]")

        if (label) label.textContent = `${index + 1} -`

        if (item.classList.contains("fleet-plate-item--availability")) {
          this.setAvailabilityDetails(item)
        }
      })
  }


  refreshUnavailableRows() {
    const unavailableList = document.getElementById("unavailable-list")

    if (!unavailableList) return

    unavailableList
      .querySelectorAll(".sortable-item")
      .forEach((item, index) => {
        const label = item.querySelector("[data-line-label]")

        if (label) label.textContent = `${index + 1} -`
      })
  }


  refreshEmptySlots() {
    const availableList = document.getElementById("available-list")
    const maxItems = Number(availableList.dataset.maxItems)

    if (!Number.isFinite(maxItems)) return

    const currentItems = availableList.querySelectorAll(".sortable-item").length
    const requiredSlots = Math.max(maxItems - currentItems, 0)
    const slots = Array.from(
      availableList.querySelectorAll(":scope > .fleet-empty-slot")
    )

    while (slots.length > requiredSlots) {
      slots.pop().remove()
    }

    while (slots.length < requiredSlots) {
      const position = availableList.children.length
      availableList.insertAdjacentHTML("beforeend", this.emptySlotHtml(position))
      slots.push(availableList.lastElementChild)
    }

    slots.forEach((slot) => this.refreshEmptySlot(slot))
  }


  adjustAvailableSlots(event) {
    const fromAvailable = event.from.id === "available-list"
    const toAvailable = event.to.id === "available-list"

    if (fromAvailable && !toAvailable) {
      event.from.insertAdjacentHTML("beforeend", this.emptySlotHtml(event.oldIndex))

      const slot = event.from.lastElementChild
      event.from.insertBefore(slot, event.from.children[event.oldIndex] || null)
    }

    if (!fromAvailable && toAvailable) {
      const slots = Array.from(
        event.to.querySelectorAll(":scope > .fleet-empty-slot")
      )
      const slotAfterItem = event.item.nextElementSibling
      const slot = slotAfterItem?.classList.contains("fleet-empty-slot")
        ? slotAfterItem
        : slots[slots.length - 1]

      if (slot) {
        event.to.insertBefore(event.item, slot)
        slot.remove()
      }
    }
  }


  emptySlotHtml(position) {
    return `
      <div class="fleet-empty-slot" data-empty-slot>
        <span>Linha ${position + 1}</span>
        <small>${this.emptySlotStandardPlateText(position)}</small>
      </div>
    `
  }


  refreshEmptySlot(slot) {
    const position = Array.from(slot.parentElement.children).indexOf(slot)
    const label = slot.querySelector("span")
    const details = slot.querySelector("small")

    if (label) label.textContent = `Linha ${position + 1}`
    if (details) details.textContent = this.emptySlotStandardPlateText(position)
  }


  emptySlotStandardPlateText(position) {
    const standardPlate = this.standardPlateForPosition(position)

    if (standardPlate) {
      return `Placa padrão da posição: ${this.escapeHtml(standardPlate)}`
    }

    return "Placa padrão da posição não definida"
  }


  refreshSpecialRoutePlaceholders() {
    this.element
      .querySelectorAll(".fleet-special-route-list")
      .forEach((list) => {
        list
          .querySelectorAll(".fleet-special-route-placeholder")
          .forEach((placeholder) => placeholder.remove())

        const maxItems = Number(list.dataset.maxItems)
        const currentItems = list.querySelectorAll(".sortable-item").length
        const emptySlots = Number.isFinite(maxItems)
          ? Math.max(maxItems - currentItems, 0)
          : 1

        for (let index = 0; index < emptySlots; index += 1) {
          list.insertAdjacentHTML(
            "beforeend",
            '<div class="fleet-special-route-placeholder">Arraste uma placa</div>'
          )
        }
      })
  }


  refreshCounts() {
    const counters = {
      available: document.querySelector("[data-count='available']"),
      exchange: document.querySelector("[data-count='exchange']"),
      unavailable: document.querySelector("[data-count='unavailable']")
    }

    const availableList = document.getElementById("available-list")
    const exchangeList = document.getElementById("exchange-list")
    const unavailableList = document.getElementById("unavailable-list")

    if (counters.available) {
      counters.available.textContent =
        `${availableList.querySelectorAll(".sortable-item").length} / ${availableList.dataset.maxItems}`
    }

    if (counters.exchange) {
      counters.exchange.textContent = exchangeList.querySelectorAll(".sortable-item").length
    }

    if (counters.unavailable) {
      counters.unavailable.textContent = unavailableList.querySelectorAll(".sortable-item").length
    }

    this.element
      .querySelectorAll("[data-special-route-count]")
      .forEach((counter) => {
        const route = counter.dataset.specialRouteCount
        const list = this.element.querySelector(`[data-special-route='${route}']`)

        if (!list) return

        counter.textContent =
          `${list.querySelectorAll(".sortable-item").length} / ${list.dataset.maxItems}`
      })
  }


  refreshCoverage() {
    const availableList = document.getElementById("available-list")
    const maxItems = Number(availableList.dataset.maxItems)

    if (!Number.isFinite(maxItems)) return

    const availableCount = availableList.querySelectorAll(".sortable-item").length
    const percentage = maxItems === 0 ? 0 : Math.round((availableCount / maxItems) * 100)
    const percentageElement = document.querySelector("[data-coverage-percentage]")
    const ratioElement = document.querySelector("[data-coverage-ratio]")

    if (percentageElement) {
      percentageElement.textContent = `${percentage}%`
    }

    if (ratioElement) {
      ratioElement.textContent = `${availableCount} / ${maxItems} linhas`
    }
  }


  refreshMaintenance() {
    const unavailableList = document.getElementById("unavailable-list")
    const totalItems = this.element.querySelectorAll(".sortable-item").length

    if (!unavailableList) return

    const maintenanceCount = Array
      .from(unavailableList.querySelectorAll(".sortable-item"))
      .filter((item) => item.dataset.reason === "maintenance")
      .length

    const percentage = totalItems === 0
      ? 0
      : Math.round((maintenanceCount / totalItems) * 100)
    const percentageElement = document.querySelector("[data-maintenance-percentage]")
    const ratioElement = document.querySelector("[data-maintenance-ratio]")

    if (percentageElement) {
      percentageElement.textContent = `${percentage}%`
    }

    if (ratioElement) {
      ratioElement.textContent = `${maintenanceCount} / ${totalItems} veículos`
    }
  }


  refreshUsedProfiles() {
    const profileCountsElement = document.querySelector("[data-used-profile-counts]")

    if (!profileCountsElement) return

    const counts = {
      VUC: 0,
      TOCO: 0,
      TRUCK: 0,
      BITRUCK: 0
    }

    this.usedItems().forEach((item) => {
      const profile = item.dataset.profile

      if (Object.prototype.hasOwnProperty.call(counts, profile)) {
        counts[profile] += 1
      }
    })

    profileCountsElement
      .querySelectorAll("[data-used-profile]")
      .forEach((profileElement) => {
        const profile = profileElement.dataset.usedProfile
        const countElement = profileElement.querySelector("[data-used-profile-count]")

        if (countElement) {
          countElement.textContent = counts[profile] || 0
        }
      })
  }


  usedItems() {
    const availableItems = Array.from(
      document.querySelectorAll("#available-list .sortable-item")
    )
    const specialRouteItems = Array.from(
      this.element.querySelectorAll(".fleet-special-route-list .sortable-item")
    )

    return availableItems.concat(specialRouteItems)
  }


  escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;")
  }



  disconnect() {

    this.sortables.forEach(sortable => {

      sortable.destroy()

    })

  }

}
