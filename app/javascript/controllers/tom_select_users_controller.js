import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (this.element.tomselect) {
      this.select = this.element.tomselect
      return
    }

    this.select = new TomSelect(this.element, {
      plugins: ['remove_button'],
      maxItems: null,
      placeholder: "Buscar responsável...",

      render: {
        option: function(data, escape) {
          return `
            <div class="d-flex align-items-center gap-2">
              <div class="avatar-circle-sm">
                ${escape(data.text.charAt(0))}
              </div>
              <span>${escape(data.text)}</span>
            </div>
          `
        },
        item: function(data, escape) {
          return `
            <div class="d-flex align-items-center gap-2">
              <div class="avatar-circle-sm">
                ${escape(data.text.charAt(0))}
              </div>
              <span>${escape(data.text.split(" ")[0])}</span>
            </div>
          `
        }
      }
    })
    for (const name of ["input", "change"]) this.select.control_input?.addEventListener(name, event => event.stopPropagation())
  }

  disconnect() { this.select?.destroy() }
}
