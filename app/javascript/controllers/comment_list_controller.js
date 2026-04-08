import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("CommentListController conectado")

    this.scrollToBottom()

    // Observa mudanças dentro da lista
    this.observer = new MutationObserver(() => {
      this.scrollToBottom()
    })

    this.observer.observe(this.element, {
      childList: true
    })
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  scrollToBottom() {
    const el = this.element
    el.scrollTo({
      top: el.scrollHeight,
      behavior: "smooth"
    })
  }
}