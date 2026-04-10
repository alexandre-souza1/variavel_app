import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.select = new TomSelect(this.element, {
      plugins: ['remove_button'],
      maxItems: null,

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
              <span>${escape(data.text)}</span>
            </div>
          `
        }
      }
    })
  }
}