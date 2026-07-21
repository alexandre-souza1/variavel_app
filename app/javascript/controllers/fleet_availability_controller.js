import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import * as bootstrap from "bootstrap"

export default class extends Controller {

  connect() {
    this.sortables = []
    this.pendingEvent = null
    this.modalConfirmed = false


    this.element.querySelectorAll(".sortable-list").forEach((list) => {

      const sortable = Sortable.create(list, {

        group: "fleet",

        animation: 150,

        draggable: ".sortable-item",

        ghostClass: "fleet-plate-item--ghost",

        onEnd: (event) => {
          this.moved(event)
        }

      })


      this.sortables.push(sortable)

    })


    this.setupModal()

  }


  moved(event) {

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
    document.getElementById("unavailableObservation").value = ""

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
    return Array
      .from(event.to.querySelectorAll(".sortable-item"))
      .indexOf(event.item)
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
  }


  setAvailabilityDetails(itemElement) {
    const setor = this.plateSetor(itemElement)
    const container = this.detailsContainer(itemElement, "fleet-plate-card__side")

    container.innerHTML = `
      <span>
        <i class="bi bi-geo-alt"></i>
        Setor ${this.escapeHtml(setor)}
      </span>
    `
  }


  setDepositDetails(itemElement) {
    const container = this.detailsContainer(itemElement, "fleet-plate-card__side")

    container.innerHTML = ""
  }


  setUnavailableDetails(itemElement, item) {
    const container = this.detailsContainer(itemElement, "fleet-plate-card__side")

    container.innerHTML = `
      <div class="fleet-plate-card__defect" data-defect>
        <strong>${this.escapeHtml(item.reason_label)}</strong>
        ${item.observation ? `<span>${this.escapeHtml(item.observation)}</span>` : ""}
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


  refreshBoard() {
    this.refreshAvailabilityRows()
    this.refreshUnavailableRows()
    this.refreshEmptySlots()
    this.refreshSpecialRoutePlaceholders()
    this.refreshCounts()
    this.refreshCoverage()
  }


  refreshAvailabilityRows() {
    const availableList = document.getElementById("available-list")

    availableList
      .querySelectorAll(".sortable-item")
      .forEach((item, index) => {
        const label = item.querySelector("[data-line-label]")

        if (label) label.textContent = `${index + 1} -`
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

    availableList
      .querySelectorAll(".fleet-empty-slot")
      .forEach((slot) => slot.remove())

    const currentItems = availableList.querySelectorAll(".sortable-item").length
    const emptySlots = Math.max(maxItems - currentItems, 0)

    for (let index = 0; index < emptySlots; index += 1) {
      availableList.insertAdjacentHTML(
        "beforeend",
        `
          <div class="fleet-empty-slot">
            <span>Linha ${currentItems + index + 1}</span>
            <small>Arraste uma placa do depósito</small>
          </div>
        `
      )
    }
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
