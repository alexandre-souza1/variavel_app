import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    this.timer = null
  }


  change() {
    clearTimeout(this.timer)

    this.timer = setTimeout(() => {
      this.element.requestSubmit()
    }, 800)
  }

}
