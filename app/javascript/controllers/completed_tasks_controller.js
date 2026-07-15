import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle(event) {
    const show = event.target.checked

    document.querySelectorAll(".completed-task").forEach(row => {
      row.classList.toggle("d-none", !show)
    })
  }
}
