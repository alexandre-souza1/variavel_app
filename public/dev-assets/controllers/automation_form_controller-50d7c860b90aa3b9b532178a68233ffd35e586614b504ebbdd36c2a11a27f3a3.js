import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "operation", "period", "actionKind", "template", "indicator", "condition", "threshold", "thresholdInput", "schedule", "hour", "weekday", "monthDay", "categories", "categoryCount"]

  connect() {
    this.indicatorOptions = [...this.indicatorTarget.options].map(option => option.cloneNode(true))
    this.refresh()
    this.updateCategories()
  }

  updateCategories() {
    const count = this.categoriesTarget.selectedOptions.length
    this.categoryCountTarget.textContent = count ? `${count} ${count === 1 ? "categoria selecionada" : "categorias selecionadas"}` : "Todas as categorias permitidas"
  }

  refresh() {
    const source = this.sourceTarget.value
    const action = this.actionKindTarget.value
    this.element.querySelectorAll("[data-automation-form-source]").forEach(fieldset => {
      fieldset.hidden = fieldset.disabled = fieldset.dataset.automationFormSource !== source
    })
    this.element.querySelectorAll("[data-automation-form-action]").forEach(fieldset => {
      fieldset.hidden = fieldset.disabled = !fieldset.dataset.automationFormAction.split(" ").includes(action)
    })
    this.restrictOptions(this.operationTarget, value => source === "invoices" || value === "count")
    this.restrictOptions(this.periodTarget, value => (source !== "fleet" || ["today", "yesterday"].includes(value)) && (action !== "update_indicator" || value !== "all"))
    this.thresholdTarget.hidden = this.thresholdInputTarget.disabled = this.conditionTarget.value === "always"
    this.thresholdInputTarget.required = this.conditionTarget.value !== "always"
    this.hourTarget.hidden = ["manual", "hourly"].includes(this.scheduleTarget.value)
    this.weekdayTarget.hidden = this.scheduleTarget.value !== "weekly"
    this.monthDayTarget.hidden = this.scheduleTarget.value !== "monthly"
    this.filterIndicators()
  }

  restrictOptions(select, allowed) {
    for (const option of select.options) option.hidden = option.disabled = !allowed(option.value)
    if (select.selectedOptions[0]?.disabled) select.value = [...select.options].find(option => !option.disabled)?.value || ""
  }

  filterIndicators() {
    const selected = this.indicatorTarget.value
    const frequencies = { today: "daily", yesterday: "daily", week: "weekly", last_week: "weekly", month: "monthly", month_to_yesterday: "daily", last_month: "monthly" }
    const frequency = frequencies[this.periodTarget.value]
    const options = this.indicatorOptions.filter(option => !option.value ||
      (option.dataset.templateId === this.templateTarget.value && option.dataset.frequency === frequency))
    this.indicatorTarget.replaceChildren(...options.map(option => option.cloneNode(true)))
    this.indicatorTarget.value = options.some(option => option.value === selected) ? selected : ""
  }
};
