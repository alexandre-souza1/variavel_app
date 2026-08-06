import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

export default class extends Controller {
  static targets = [
    "subtitle",
    "list",
    "empty",
    "body",
    "submit"
  ]

  connect() {
    this.routineValueId = null
    this.open = this.open.bind(this)

    document.addEventListener("routine-comments:open", this.open)
  }

  disconnect() {
    document.removeEventListener("routine-comments:open", this.open)
  }

  async open(event) {
    this.routineValueId = event.detail.routineValueId
    this.subtitleTarget.textContent = this.subtitle(event.detail)
    this.bodyTarget.value = ""
    this.setLoading()

    this.modal.show()

    await this.loadComments()
  }

  async loadComments() {
    const response = await fetch(this.commentsPath, {
      headers: {
        "Accept": "application/json"
      }
    })

    if (!response.ok) {
      this.showError("Não foi possível carregar os comentários.")
      return
    }

    const data = await response.json()
    this.renderComments(data.comments)
    this.broadcastCount(data.count)
  }

  async create(event) {
    event.preventDefault()

    const body = this.bodyTarget.value.trim()
    if (body === "") return

    this.submitTarget.disabled = true

    const response = await fetch(this.commentsPath, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({
        routine_comment: {
          body: body
        }
      })
    })

    this.submitTarget.disabled = false

    if (!response.ok) {
      this.showError("Não foi possível salvar o comentário.")
      return
    }

    const data = await response.json()
    this.bodyTarget.value = ""
    this.appendComment(data.comment)
    this.updateEmptyState()
    this.broadcastCount(data.count)
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
