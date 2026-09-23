import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "messages", "question", "submit"]

  handleKeydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    if (!this.submitTarget.disabled) this.formTarget.requestSubmit()
  }

  async submit(event) {
    event.preventDefault()

    const question = this.questionTarget.value.trim()
    if (!question || this.submitTarget.disabled) return

    const formData = new FormData(this.formTarget)
    const pageParams = new URLSearchParams(window.location.search)
    const month = pageParams.get("periodo_mes")
    const year = pageParams.get("periodo_ano") || String(new Date().getFullYear())
    if (/^(?:[1-9]|1[0-2])$/.test(month || "") && /^\d{4}$/.test(year)) {
      formData.set("consumption_period", `${year}-${month.padStart(2, "0")}`)
    }
    this.appendMessage("user", question)
    const loadingMessage = this.appendLoadingMessage()
    this.questionTarget.value = ""
    this.submitTarget.disabled = true
    this.questionTarget.disabled = true

    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: new URLSearchParams(formData)
      })
      const payload = await response.json()

      if (!response.ok) throw new Error(payload.error || "Não foi possível responder agora.")

      loadingMessage.replaceWith(this.createMessageElement("assistant", this.cleanAssistantText(payload.answer)))
    } catch (error) {
      loadingMessage.replaceWith(this.createMessageElement("assistant", error.message, true))
    } finally {
      this.submitTarget.disabled = false
      this.questionTarget.disabled = false
      this.questionTarget.focus()
      this.scrollToBottom()
    }
  }

  appendMessage(role, content) {
    this.messagesTarget.appendChild(this.createMessageElement(role, content))
    this.scrollToBottom()
  }

  appendLoadingMessage() {
    const message = document.createElement("div")
    message.className = "public-variable-chat-message public-variable-chat-message--assistant public-variable-chat-message--loading"
    message.innerHTML = `
      <span>Assistente</span>
      <div class="public-variable-chat-loading" aria-label="A IA está preparando a resposta">
        <i></i><i></i><i></i>
      </div>
    `
    this.messagesTarget.appendChild(message)
    this.scrollToBottom()
    return message
  }

  createMessageElement(role, content, error = false) {
    const message = document.createElement("div")
    message.className = `public-variable-chat-message public-variable-chat-message--${role}${error ? " public-variable-chat-message--error" : ""}`

    const author = document.createElement("span")
    author.textContent = role === "user" ? "Você" : "Assistente"

    const body = document.createElement("div")
    body.textContent = content

    message.append(author, body)
    return message
  }

  cleanAssistantText(content) {
    return String(content || "")
      .replace(/\\n/g, "\n")
      .replace(/\\(?:\r?\n|$)/g, "\n")
      .replace(/\\([*_~-])/g, "$1")
      .replace(/\*\*(.*?)\*\*/g, "$1")
      .replace(/^\s*\*\s+/gm, "• ")
      .trim()
  }

  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
}
