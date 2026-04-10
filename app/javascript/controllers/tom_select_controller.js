import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (this.element.tomselect) return

    this.element.tomselect = new TomSelect(this.element, {
      plugins: ["remove_button"],
      persist: false,
      create: false,
      placeholder: "Selecione...",

      render: {
        option: (data, escape) => {
        return `
            <div class="d-flex align-items-center gap-2">
            <span style="
                width:10px;
                height:10px;
                border-radius:50%;
                background:${data.color || "#999"}
            "></span>
            <span>${escape(data.text)}</span>
            </div>
        `
        },

        item: (data, escape) => {
        return `
            <div class="d-flex align-items-center gap-2">
            <span style="
                width:10px;
                height:10px;
                border-radius:50%;
                background:${data.color || "#999"}
            "></span>
            <span>${escape(data.text)}</span>
            </div>
        `
        }
      }
    })
  }
}