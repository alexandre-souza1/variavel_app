import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"
import { showFlash } from "controllers/flash_controller"

export default class extends Controller {
  static targets = [
    "subtitle",
    "list",
    "empty",
    "body",
    "submit",
    "taskHint",
    "assigneeSection", "assigneeTrigger", "assigneeAvatars", "assigneeAdd",
    "assigneePicker", "assigneeSelect", "assigneeStatus"
  ]

  connect() {
    this.routineValueId = null
    this.open = this.open.bind(this)

    document.addEventListener("routine-comments:open", this.open)
    this.repositionAssignees = this.positionAssigneePicker.bind(this)
    document.addEventListener("scroll", this.repositionAssignees, true)
    window.visualViewport?.addEventListener("resize", this.repositionAssignees)
    window.visualViewport?.addEventListener("scroll", this.repositionAssignees)
    this.assigneeResizeObserver = new ResizeObserver(this.repositionAssignees)
    this.assigneeResizeObserver.observe(this.assigneePickerTarget)
  }

  disconnect() {
    document.removeEventListener("routine-comments:open", this.open)
    this.loadRequest?.abort()
    this.hideAssignees()
    this.assigneeResizeObserver.disconnect()
    document.removeEventListener("scroll", this.repositionAssignees, true)
    window.visualViewport?.removeEventListener("resize", this.repositionAssignees)
    window.visualViewport?.removeEventListener("scroll", this.repositionAssignees)
  }

  async open(event) {
    this.openVersion = (this.openVersion || 0) + 1
    this.routineValueId = event.detail.routineValueId
    this.subtitleTarget.textContent = this.subtitle(event.detail)
    this.bodyTarget.value = ""
    this.taskHintTarget.classList.add("d-none")
    this.assigneeSectionTarget.hidden = true
    this.hideAssignees()
    this.assigneeStatusTarget.textContent = ""
    this.assigneeTriggerTarget.setAttribute("aria-expanded", "false")
    this.submitTarget.disabled = true
    this.setLoading()

    this.modal.show()

    await this.loadComments()
  }

  async loadComments() {
    this.loadRequest?.abort()
    this.loadRequest = new AbortController()
    const version = this.openVersion
    try {
      const response = await fetch(this.commentsPath, {
        signal: this.loadRequest.signal,
        headers: {
          "Accept": "application/json"
        }
      })

      if (version !== this.openVersion) return
      if (!response.ok) {
        this.showError("Não foi possível carregar os comentários.")
        return
      }

      const data = await response.json()
      if (version !== this.openVersion) return
      this.renderComments(data.comments)
      this.broadcastCount(data.count)
      this.updateTaskHint(data)
      this.configureAssignees(data)
      this.submitTarget.disabled = false
    } catch (error) {
      if (error.name !== "AbortError" && version === this.openVersion) this.showError("Não foi possível carregar os comentários.")
    }
  }

  async create(event) {
    event.preventDefault()
    if (this.submitTarget.disabled) return

    const body = this.bodyTarget.value.trim()
    if (body === "") return

    const version = this.openVersion
    this.submitTarget.disabled = true
    this.setAssigneeControlsDisabled(true)

    try {
      const response = await fetch(this.commentsPath, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({ routine_comment: { body: body } })
      })
      if (!response.ok) throw new Error("save failed")

      const data = await response.json()
      if (version !== this.openVersion) return
      this.bodyTarget.value = ""
      this.appendComment(data.comment)
      this.updateEmptyState()
      this.broadcastCount(data.count)
      if (data.generated_task_created) {
        showFlash("Comentário salvo e tarefa criada no plano.", { url: data.generated_task_url })
        this.taskHintTarget.textContent = "Cada novo comentário desta célula vai gerar uma tarefa separada no bucket da categoria."
      }
    } catch {
      if (version === this.openVersion) this.showError("Não foi possível salvar o comentário.")
    } finally {
      if (version === this.openVersion) {
        this.submitTarget.disabled = false
        this.setAssigneeControlsDisabled(false)
      }
    }
  }

  updateTaskHint(data) {
    if (!data.can_generate_task) return
    if (data.cell_status === "danger") {
      this.taskHintTarget.textContent = "O indicador está fora da meta. Cada comentário vai gerar uma tarefa separada no bucket da categoria."
    } else {
      this.taskHintTarget.textContent = "O comentário fica registrado no GEROT. Uma tarefa só é gerada para indicadores fora da meta."
    }
    this.taskHintTarget.classList.remove("d-none")
  }

  configureAssignees(data) {
    this.assignees = data.available_assignees
    this.selectedAssignees = data.indicator_assignees
    this.canManageAssignees = data.can_manage_assignees
    this.assigneeSectionTarget.hidden = !data.has_action_plan
    this.assigneeTriggerTarget.disabled = !this.canManageAssignees
    this.assigneeTriggerTarget.setAttribute("aria-label", this.canManageAssignees ? "Selecionar responsáveis do indicador" : "Responsáveis do indicador")
    this.assigneeAddTarget.hidden = !this.canManageAssignees
    const select = this.assigneeSelectTarget.tomselect
    const users = this.canManageAssignees ? this.assignees : this.selectedAssignees
    select.clear(true)
    select.clearOptions()
    select.addOptions(users.map(user => ({ value: String(user.id), text: user.name })))
    select.setValue(this.selectedAssignees.map(user => String(user.id)), true)
    this.setAssigneeControlsDisabled(false)
    this.renderAssigneeAvatars()
  }

  assigneeAvatar(user) {
    const avatar = document.createElement("span")
    avatar.className = "avatar-circle-sm"
    avatar.textContent = user.name.trim().charAt(0).toLocaleUpperCase("pt-BR")
    avatar.title = user.name
    return avatar
  }

  renderAssigneeAvatars() {
    const users = this.selectedAssignees
    this.assigneeAvatarsTarget.replaceChildren(...users.slice(0, 3).map(user => this.assigneeAvatar(user)))
    if (users.length > 3) {
      const extra = document.createElement("span")
      extra.className = "avatar-circle-sm extra"
      extra.textContent = `+${users.length - 3}`
      extra.title = users.slice(3).map(user => user.name).join(", ")
      this.assigneeAvatarsTarget.append(extra)
    }
    this.assigneeTriggerTarget.title = users.length ? users.map(user => user.name).join(", ") : "Sem responsáveis fixos. A tarefa será atribuída ao autor do comentário."
  }

  toggleAssignees() {
    if (!this.canManageAssignees) return
    if (!this.assigneePickerTarget.hidden) {
      this.hideAssignees()
      this.assigneeTriggerTarget.focus({ preventScroll: true })
      return
    }
    this.assigneePickerTarget.hidden = false
    this.assigneePickerTarget.showPopover()
    this.assigneeTriggerTarget.setAttribute("aria-expanded", "true")
    this.positionAssigneePicker()
    this.assigneeSelectTarget.tomselect.focus()
    this.assigneeSelectTarget.tomselect.open()
    this.positionAssigneePicker()
  }

  hideAssignees() {
    this.assigneeSelectTarget.tomselect?.close()
    this.assigneePickerTarget.hidePopover()
    this.assigneePickerTarget.hidden = true
    this.assigneeTriggerTarget.setAttribute("aria-expanded", "false")
  }

  outsideAssignees(event) {
    if (!this.assigneePickerTarget.hidden && !this.assigneePickerTarget.contains(event.target) && !this.assigneeTriggerTarget.contains(event.target)) this.hideAssignees()
  }

  escapeAssignees(event) {
    if (this.assigneePickerTarget.hidden) return
    event.preventDefault()
    event.stopPropagation()
    this.hideAssignees()
    this.assigneeTriggerTarget.focus({ preventScroll: true })
  }

  positionAssigneePicker(event) {
    const panel = this.assigneePickerTarget
    if (panel.hidden || (event?.type === "scroll" && event.target instanceof Node && panel.contains(event.target))) return
    const anchor = this.assigneeTriggerTarget.getBoundingClientRect()
    const viewport = window.visualViewport
    const width = viewport?.width || window.innerWidth
    const height = viewport?.height || window.innerHeight
    const top = viewport?.offsetTop || 0
    const left = viewport?.offsetLeft || 0
    const gap = 8
    const below = top + height - anchor.bottom - gap - 12
    const above = anchor.top - top - gap - 12
    const upwards = below < 320 && above > below
    panel.style.width = `${Math.min(340, width - 24)}px`
    panel.style.maxHeight = `${Math.max(0, Math.min(380, height - 24, upwards ? above : below))}px`
    panel.style.left = `${Math.max(left + 12, Math.min(anchor.left, left + width - panel.offsetWidth - 12))}px`
    const panelTop = upwards ? anchor.top - panel.offsetHeight - gap : anchor.bottom + gap
    panel.style.top = `${Math.max(top + 12, Math.min(panelTop, top + height - panel.offsetHeight - 12))}px`
  }

  setAssigneeControlsDisabled(disabled) {
    this.assigneeTriggerTarget.disabled = disabled || !this.canManageAssignees
    const select = this.assigneeSelectTarget.tomselect
    if (disabled || !this.canManageAssignees) select.disable()
    else select.enable()
  }

  async saveAssignees() {
    const valueId = this.routineValueId
    const version = this.openVersion
    const select = this.assigneeSelectTarget.tomselect
    const ids = select.getValue().map(Number)
    select.disable()
    this.submitTarget.disabled = true
    this.assigneeStatusTarget.classList.remove("text-danger")
    this.assigneeStatusTarget.textContent = "Salvando responsáveis…"
    try {
      const response = await fetch(`/routine_values/${valueId}/indicator_assignees`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": this.csrfToken },
        body: JSON.stringify({ routine_indicator: { user_ids: ids } })
      })
      if (!response.ok) throw new Error("save failed")
      const data = await response.json()
      if (version !== this.openVersion) return
      this.selectedAssignees = this.assignees.filter(user => data.user_ids.includes(user.id))
      this.renderAssigneeAvatars()
      this.assigneeStatusTarget.textContent = "Responsáveis salvos no indicador."
    } catch {
      if (version !== this.openVersion) return
      select.setValue(this.selectedAssignees.map(user => String(user.id)), true)
      this.assigneeStatusTarget.classList.add("text-danger")
      this.assigneeStatusTarget.textContent = "Não foi possível salvar os responsáveis. Tente novamente."
    } finally {
      if (version === this.openVersion) {
        select.enable()
        this.submitTarget.disabled = false
      }
    }
  }

  async destroy(event) {
    event.preventDefault()

    const commentElement = event.target.closest("[data-comment-id]")
    if (!commentElement) return

    const response = await fetch(
      `${this.commentsPath}/${commentElement.dataset.commentId}`,
      {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": this.csrfToken,
          "Accept": "application/json"
        }
      }
    )

    if (!response.ok) {
      this.showError("Não foi possível remover o comentário.")
      return
    }

    const data = await response.json()
    commentElement.remove()
    this.updateEmptyState()
    this.broadcastCount(data.count)
  }

  setLoading() {
    this.listTarget.innerHTML = `
      <div class="text-muted small py-3">
        Carregando comentários...
      </div>
    `
    this.emptyTarget.classList.add("d-none")
  }

  renderComments(comments) {
    this.listTarget.innerHTML = ""

    comments.forEach((comment) => {
      this.appendComment(comment)
    })

    this.updateEmptyState()
  }

  appendComment(comment) {
    this.listTarget.appendChild(this.commentElement(comment))
  }

  commentElement(comment) {
    const wrapper = document.createElement("div")
    wrapper.className = "routine-comment"
    wrapper.dataset.commentId = comment.id

    const header = document.createElement("div")
    header.className = "routine-comment__header"

    const meta = document.createElement("div")
    meta.className = "routine-comment__meta"

    const user = document.createElement("strong")
    user.textContent = comment.user_name

    const time = document.createElement("span")
    time.className = "routine-comment__time"
    time.textContent = comment.created_at

    meta.appendChild(user)
    meta.appendChild(time)
    header.appendChild(meta)

    if (comment.can_destroy) {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "btn btn-sm btn-link text-danger p-0"
      button.textContent = "Remover"
      button.dataset.action = "click->routine-comments#destroy"

      header.appendChild(button)
    }

    const body = document.createElement("div")
    body.className = "routine-comment__body"
    body.textContent = comment.body

    wrapper.appendChild(header)
    wrapper.appendChild(body)

    return wrapper
  }

  updateEmptyState() {
    const hasComments = this.listTarget.children.length > 0
    this.emptyTarget.classList.toggle("d-none", hasComments)
  }

  showError(message) {
    this.listTarget.innerHTML = ""

    const alert = document.createElement("div")
    alert.className = "alert alert-danger mb-0"
    alert.textContent = message

    this.listTarget.appendChild(alert)
    this.emptyTarget.classList.add("d-none")
  }

  broadcastCount(count) {
    document.dispatchEvent(
      new CustomEvent(
        "routine-comments:count-updated",
        {
          detail: {
            routineValueId: this.routineValueId,
            count: count
          }
        }
      )
    )
  }

  subtitle(detail) {
    return [
      detail.indicatorName,
      detail.referenceDate,
      detail.value
    ].filter(Boolean).join(" - ")
  }

  get commentsPath() {
    return `/routine_values/${this.routineValueId}/routine_comments`
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']").content
  }

  get modal() {
    return bootstrap.Modal.getOrCreateInstance(this.element)
  }
}
