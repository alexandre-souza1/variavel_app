import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  static values = { taskId: Number }

  connect() {
    this.beforeCache = () => this.close(false)
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.close(false)
  }

  async open(event) {
    if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    if (this.opening || this.modal) return
    this.opening = true
    try {
      const response = await fetch(this.element.href, { headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" } })
      if (!response.ok) throw new Error("Não foi possível abrir o cadastro. Tente novamente.")
      const html = await response.text()
      if (!this.element.isConnected) return
      const parent = this.element.closest(".modal.show")
      if (parent) {
        this.parentModal = Modal.getOrCreateInstance(parent)
        await this.hide(this.parentModal, parent)
      }
      this.container = document.createElement("div")
      this.container.innerHTML = html
      document.body.append(this.container)
      const element = this.container.querySelector(".modal")
      this.modal = new Modal(element)
      element.addEventListener("hidden.bs.modal", () => {
        this.modal?.dispose()
        this.modal = null
        this.container.remove()
        if (this.restoreParent !== false) this.parentModal?.show()
        this.parentModal = null
        if (this.element.isConnected && this.restoreParent !== false) this.element.focus()
      }, { once: true })
      this.restoreParent = true
      this.bindForm()
      element.addEventListener("shown.bs.modal", () => element.querySelector('input[name="historical_employee[nome]"]')?.focus(), { once: true })
      this.modal.show()
    } catch (error) {
      this.message(this.element.parentElement, error.message, "danger")
    } finally {
      this.opening = false
    }
  }

  bindForm() {
    this.container.querySelector("form").addEventListener("submit", event => this.save(event))
  }

  async save(event) {
    event.preventDefault()
    if (this.saving) return
    const form = event.currentTarget
    const button = form.querySelector('[type="submit"]')
    this.saving = button.disabled = true
    try {
      const response = await fetch(form.action, {
        method: "POST", body: new FormData(form),
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      })
      if (![201, 422].includes(response.status)) throw new Error("Não foi possível cadastrar. Confira seu acesso e tente novamente.")
      const result = await response.json()
      if (response.status === 422 && this.modal) {
        const next = new DOMParser().parseFromString(result.html, "text/html")
        this.container.querySelector(".modal-content").replaceWith(next.querySelector(".modal-content"))
        this.bindForm()
        const alert = this.container.querySelector('[role="alert"]')
        alert?.setAttribute("tabindex", "-1")
        alert?.focus()
        return
      }
      if (!response.ok) throw new Error("Não foi possível cadastrar. Confira os dados e tente novamente.")
      await this.close()
      await this.refreshChoices(result.employee)
      const context = this.hasTaskIdValue ? document.getElementById(`task-checklist-occurrences-${this.taskIdValue}`) : document.getElementById("tracking-review")
      this.message(context || this.element.parentElement, result.message, "success")
    } catch (error) {
      this.message(this.container?.querySelector(".modal-body") || this.element.parentElement, error.message, "danger")
    } finally {
      this.saving = false
      if (button.isConnected) button.disabled = false
    }
  }

  async refreshChoices(employee) {
    let page
    const toolbar = document.getElementById("tracking-review-toolbar")
    if (toolbar) {
      try {
        const response = await fetch(window.location.href, { headers: { Accept: "text/html" } })
        if (response.ok) page = new DOMParser().parseFromString(await response.text(), "text/html")
      } catch (_error) { /* The saved employee can still be selected without refreshing the summary. */ }
    }
    document.querySelectorAll('select[name="checklist_occurrence[employee_id]"]').forEach(select => {
      const fresh = page?.getElementById(select.id)
      if (fresh && !fresh.querySelector(`option[value="${employee.id}"]`)) return
      if (select.tomselect) select.tomselect.addOption({ value: String(employee.id), text: employee.label })
      else if (![...select.options].some(option => option.value === String(employee.id))) select.add(new Option(employee.label, employee.id))
      const chosen = select.id === `occurrence-employee-${this.taskIdValue}` ? String(employee.id) : (!select.value ? fresh?.value : null)
      if (chosen) {
        if (select.tomselect) select.tomselect.setValue(chosen)
        else { select.value = chosen; select.dispatchEvent(new Event("change", { bubbles: true })) }
        const kind = document.getElementById(select.id.replace("occurrence-employee-", "occurrence-kind-"))
        const freshKind = page?.getElementById(kind?.id)
        const initialKind = kind && [...kind.options].find(option => option.defaultSelected)?.value
        if (fresh?.value === chosen && freshKind && kind.value === initialKind) {
          if (kind.tomselect) kind.tomselect.setValue(freshKind.value)
          else kind.value = freshKind.value
        }
      }
    })
    if (page) {
      const nextToolbar = page.getElementById("tracking-review-toolbar")
      if (nextToolbar) toolbar.replaceWith(nextToolbar)
      page.querySelectorAll('.checklist-tracking__candidate').forEach(candidate => {
        const reason = candidate.querySelector('details > .checklist-tracking__explanation')
        const current = document.getElementById(candidate.id)?.querySelector('details > .checklist-tracking__explanation')
        if (reason && current) current.replaceWith(reason)
      })
    }
  }

  message(context, text, kind) {
    if (!context?.isConnected) return
    const alert = document.createElement("p")
    alert.className = `alert alert-${kind} mt-2`
    alert.setAttribute("role", kind === "danger" ? "alert" : "status")
    alert.textContent = text
    context.prepend(alert)
  }

  hide(modal, element) {
    if (!element?.classList.contains("show")) return Promise.resolve()
    return new Promise(resolve => {
      element.addEventListener("hidden.bs.modal", resolve, { once: true })
      modal.hide()
    })
  }

  close(restoreParent = true) {
    this.restoreParent = restoreParent
    return this.modal ? this.hide(this.modal, this.container.querySelector('.modal')) : Promise.resolve()
  }
}
