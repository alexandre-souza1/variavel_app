import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  open(event) {
    event.preventDefault()
    window.dispatchEvent(new CustomEvent("meeting-recorder:open"))
  }
}
