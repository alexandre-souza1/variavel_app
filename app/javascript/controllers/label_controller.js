import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    actionPlanId: Number
  }

  static targets = ["name", "color", "select"]

  create() {
    console.log("ACTION PLAN:", this.actionPlanIdValue)

    const name = this.nameTarget.value.trim()
    const color = this.colorTarget.value

    if (!name) {
      alert("Digite um nome para a label")
      return
    }

    fetch("/labels", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({
        label: {
          name: name,
          color: color,
          action_plan_id: this.actionPlanIdValue
        }
      })
    })
      .then(response => response.json())
      .then(data => {
        if (data.errors) {
          alert(data.errors.join(", "))
          return
        }

        this.addLabelToSelect(data)

        this.nameTarget.value = ""
        this.colorTarget.value = "#000000"
      })
  }

  addLabelToSelect(label) {
    const select = this.element.querySelector('[data-controller="tom-select"]')

    if (!select.tomselect) return

    const tom = select.tomselect

    // adiciona opção
    tom.addOption({
        value: label.id,
        text: label.name,
        color: label.color
    })

    // força atualização interna
    tom.refreshOptions(false)

    // seleciona automaticamente
    tom.addItem(label.id)
  }
}