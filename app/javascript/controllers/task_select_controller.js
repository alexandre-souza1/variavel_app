import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { search: { type: Boolean, default: true }, placeholder: String }

  connect() {
    if (this.element.tomselect) return
    this.select = new TomSelect(this.element, {
      maxItems: 1,
      create: false,
      allowEmptyOption: true,
      hideSelected: false,
      placeholder: this.placeholderValue,
      ...(this.searchValue ? {} : { controlInput: null }),
      render: {
        option: (data, escape) => `<div class="task-select-option"><span>${escape(data.text)}</span><i class="bi bi-check2" aria-hidden="true"></i></div>`
      }
    })
    for (const name of ["input", "change"]) this.select.control_input?.addEventListener(name, event => event.stopPropagation())
  }

  disconnect() { this.select?.destroy() }
}
