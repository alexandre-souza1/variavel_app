import { Controller } from "@hotwired/stimulus"
import { showFlash } from "controllers/flash_controller"

export default class extends Controller {
  static targets = ["list", "empty", "badge", "headerCount", "deleteAll", "dailySummaryToggle"]
  static values = { deleteAllUrl: String }

  keepOpen(event) {
    event.stopPropagation()
  }

  async updatePreferences(event) {
    event.preventDefault()
    event.stopPropagation()
    const form = event.currentTarget
    const toggle = this.dailySummaryToggleTarget
    const enabled = toggle.checked
    const data = new FormData(form)
    toggle.disabled = true

    try {
      const result = await this.request(form.action, form.method || "post", data)
      toggle.checked = result.daily_summary_enabled
      showFlash(result.message, { type: "success" })
    } catch {
      toggle.checked = !enabled
      showFlash("Não foi possível salvar a preferência. Tente novamente.", { type: "danger" })
    } finally {
      toggle.disabled = false
    }
  }

  async destroy(event) {
    event.preventDefault()
    event.stopPropagation()

    const form = event.currentTarget
    const item = form.closest("[data-notifications-target='item']")

    try {
      const result = await this.request(form.action, form.method || "post", new FormData(form))
      item?.remove()
      this.refresh(result)
    } catch (error) {
      console.error("Não foi possível apagar a notificação.", error)
    }
  }

  async destroyAll(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    if (!window.confirm("Deseja apagar todas as notificações?")) return

    button.disabled = true

    try {
      const result = await this.request(this.deleteAllUrlValue, "delete")
      this.listTarget.replaceChildren()
      this.refresh(result)
    } catch (error) {
      button.disabled = false
      console.error("Não foi possível apagar as notificações.", error)
    }
  }

  async request(url, method, body = null) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(url, {
      method,
      body,
      headers: {
        Accept: "application/json",
        ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
      },
      credentials: "same-origin"
    })

    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    return response.json()
  }

  refresh(result) {
    const unreadCount = Number(result.unread_count || 0)
    const notificationCount = Number(result.notification_count || this.listTarget.children.length)

    this.badgeTarget.textContent = unreadCount
    this.badgeTarget.classList.toggle("d-none", unreadCount === 0)

    if (this.hasHeaderCountTarget) {
      this.headerCountTarget.textContent = unreadCount
      this.headerCountTarget.setAttribute("aria-label", `${unreadCount} não lidas`)
      this.headerCountTarget.classList.toggle("d-none", unreadCount === 0)
    }

    if (this.hasDeleteAllTarget) {
      this.deleteAllTarget.classList.toggle("d-none", notificationCount === 0)
    }

    this.emptyTarget.classList.toggle("d-none", notificationCount !== 0)
  }
}
