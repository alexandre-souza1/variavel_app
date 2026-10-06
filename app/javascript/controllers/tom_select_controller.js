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
      options: Array.from(this.element.options, option => ({
        value: option.value,
        text: option.text.trim(),
        color: option.dataset.color
      })),

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
              <span class="action-plan-color-badge" style="--task-label-color: ${escape(this.badgeColor(data.color))}">${escape(data.text)}</span>
            </div>
          `
        },

        item: (data, escape) => {
          return `
            <div class="action-plan-color-badge" style="--task-label-color: ${escape(this.badgeColor(data.color))}">
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
    for (const name of ["input", "change"]) this.tom.control_input?.addEventListener(name, event => event.stopPropagation())
  }

  disconnect() { this.tom?.destroy() }

  randomColor() {
    const colors = ["#ef4444", "#22c55e", "#3b82f6", "#eab308", "#a855f7"]
    return colors[Math.floor(Math.random() * colors.length)]
  }

  badgeColor(color) {
    return /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i.test(color || "") ? color : "#6b7280"
  }
}
