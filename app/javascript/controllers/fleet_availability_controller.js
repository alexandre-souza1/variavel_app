import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import * as bootstrap from "bootstrap"

export default class extends Controller {

  connect() {
    console.log("FleetAvailability conectado")
    this.sortables = []
    this.pendingEvent = null


    this.element.querySelectorAll(".sortable-list").forEach((list) => {

      const sortable = Sortable.create(list, {

        group: "fleet",

        animation: 150,

        ghostClass: "bg-light",

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


    const status = statusMap[event.to.id]


    if (status === "unavailable") {

      this.pendingEvent = event

      this.openModal()

      return
    }


    this.updateItem(
      itemId,
      status,
      event.newIndex
    )

  }


  openModal() {

    const modalElement = document.getElementById(
      "unavailableModal"
    )


    const modal = new bootstrap.Modal(
      modalElement
    )


    modal.show()

  }


  setupModal() {

    const button = document.getElementById(
      "confirmUnavailable"
    )


    if (!button) return


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



      this.updateItem(
        itemId,
        "unavailable",
        event.newIndex,
        reason,
        observation
      )


      bootstrap.Modal
        .getInstance(
          document.getElementById("unavailableModal")
        )
        .hide()


      this.pendingEvent = null

    })

  }


  updateItem(
    itemId,
    status,
    position,
    reason = null,
    observation = null
  ) {


    fetch(
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

            observation: observation

          }

        })

      }

    )

  }



  disconnect() {

    this.sortables.forEach(sortable => {

      sortable.destroy()

    })

  }

}
