import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle(event) {
    const checkbox = event.target
    const label = checkbox.closest('.form-check').querySelector('.form-check-label')
    if (checkbox.checked) {
      label.classList.add('text-decoration-line-through')
    } else {
      label.classList.remove('text-decoration-line-through')
    }
  }
}
