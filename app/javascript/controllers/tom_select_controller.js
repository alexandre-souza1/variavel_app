import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    actionPlanId: Number
  }

  connect() {

    if (this.element.tomselect) return

    this.tom = new TomSelect(this.element, {
      placeholder: "Adicionar rótulo...",
      valueField: "value",
      labelField: "text",
      searchField: "text",
      plugins: ['remove_button'], // 🔥 aqui

      onInitialize: function() {
        const select = this.input

        select.querySelectorAll("option").forEach(option => {
          this.addOption({
            value: option.value,
            text: option.text,
            color: option.dataset.color
          })
        })
      },

      render: {
        option_create: (data, escape) => {
          return `
            <div class="create">
              ➕ Adicionar "<strong>${escape(data.input)}</strong>"
            </div>
          `
        },

        option: (data, escape) => {
          return `
            <div class="d-flex align-items-center gap-2">
              <span style="
                width: 10px;
                height: 10px;
                border-radius: 50%;
                background: ${data.color || '#ccc'};
                display: inline-block;
              "></span>
              <span>${escape(data.text)}</span>
            </div>
          `
        },

        item: (data, escape) => {
          return `
            <div style="
              background: ${data.color || '#ccc'};
              color: white;
              padding: 2px 8px;
              border-radius: 12px;
              font-size: 12px;
            ">
              ${escape(data.text)}
            </div>
          `
        }
      },

      create: (input, callback) => {
        fetch("/labels", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
          },
          body: JSON.stringify({
            label: {
              name: input,
              color: this.randomColor(),
              action_plan_id: this.actionPlanIdValue
            }
          })
        })
          .then(response => response.json())
          .then(data => {
            if (data.errors) {
              alert(data.errors.join(", "))
              callback()
              return
            }

            callback({
              value: data.id,
              text: data.name,
              color: data.color
            })
          })
      }
    })
  }

  randomColor() {
    const colors = ["#ef4444", "#22c55e", "#3b82f6", "#eab308", "#a855f7"]
    return colors[Math.floor(Math.random() * colors.length)]
  }
}
