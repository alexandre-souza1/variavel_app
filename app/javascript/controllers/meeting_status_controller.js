import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { interval: { type: Number, default: 4000 } }

  connect() {
    this.timer = window.setTimeout(() => window.location.reload(), this.intervalValue)
  }

  disconnect() {
    window.clearTimeout(this.timer)
  }
}
