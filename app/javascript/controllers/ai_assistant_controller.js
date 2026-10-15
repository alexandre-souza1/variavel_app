import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["launcher", "panel", "messages", "welcome", "question", "send", "clear", "status", "error"]
  static values = { url: String }

  connect() {
    this.alive = true
    this.processing = false
    this.requesting = false
  }

  disconnect() {
    this.alive = false
    clearTimeout(this.pollTimer)
    this.abortController?.abort()
  }

  async open() {
    this.panelTarget.hidden = false
    this.launcherTarget.hidden = true
    this.launcherTarget.setAttribute("aria-expanded", "true")
    window.dispatchEvent(new CustomEvent("ai-assistant:opened"))
    await this.load()
    if (this.alive && !this.panelTarget.hidden) this.questionTarget.focus()
  }

  close(event) {
    this.panelTarget.hidden = true
    this.launcherTarget.hidden = false
    this.launcherTarget.setAttribute("aria-expanded", "false")
    clearTimeout(this.pollTimer)
    if (["click", "keydown"].includes(event?.type)) this.launcherTarget.focus()
  }

  beforeCache() {
    this.close()
    this.abortController?.abort()
    this.messagesTarget.replaceChildren()
    this.questionTarget.value = ""
  }

  async request(method = "GET", body) {
    this.abortController = new AbortController()
    const timeout = setTimeout(() => this.abortController?.abort(), 15000)
    try {
      const response = await fetch(this.urlValue, {
        method, credentials: "same-origin", cache: "no-store", signal: this.abortController.signal,
        headers: { "Accept": "application/json", "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body: body ? JSON.stringify(body) : undefined
      })
      if (response.redirected || response.status === 401) throw new Error("Sua sessão expirou. Entre novamente no app.")
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Não foi possível consultar o assistente.")
      return data
    } finally {
      clearTimeout(timeout)
    }
  }

  async load() {
    if (this.requesting) return
    this.requesting = true
    this.updateControls()
    try {
      this.render(await this.request())
    } catch (error) {
      this.showError(error)
      if (this.processing) this.schedulePoll()
    } finally {
      this.requesting = false
      if (this.alive) this.updateControls()
    }
  }

  async send(event) {
    event?.preventDefault()
    const question = this.questionTarget.value.trim()
    if (!question || this.processing || this.requesting) return
    clearTimeout(this.pollTimer)
    this.requesting = true
    this.errorTarget.hidden = true
    this.updateControls()
    try {
      const data = await this.request("POST", { question })
      if (!this.alive) return
      this.questionTarget.value = ""
      this.render(data)
    } catch (error) {
      this.showError(error)
      // Uma resposta de rede perdida pode ter iniciado um trabalho no servidor.
      this.schedulePoll()
    } finally {
      this.requesting = false
      if (this.alive) this.updateControls()
    }
  }

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault()
      this.send()
    }
  }

  suggest(event) {
    if (this.processing || this.requesting) return
    this.questionTarget.value = event.currentTarget.dataset.question
    this.send()
  }

  async clear() {
    if (this.requesting) return
    if (!window.confirm("Limpar o histórico do seu assistente?")) return
    clearTimeout(this.pollTimer)
    this.requesting = true
    this.updateControls()
    try {
      this.render(await this.request("DELETE"))
    } catch (error) {
      this.showError(error)
      if (this.processing) this.schedulePoll()
    } finally {
      this.requesting = false
      if (this.alive) this.updateControls()
    }
  }

  render(data) {
    if (!this.alive) return
    this.processing = data.processing
    const atBottom = this.messagesTarget.scrollHeight - this.messagesTarget.scrollTop - this.messagesTarget.clientHeight < 60
    const fragment = document.createDocumentFragment()
    for (const message of data.messages) {
      const article = document.createElement("article")
      article.className = `ai-assistant__message ai-assistant__message--${message.role === "user" ? "user" : "assistant"}`
      const label = document.createElement("small")
      label.textContent = message.role === "user" ? "Você" : "Assistente IA"
      const content = document.createElement("p")
      content.textContent = message.content
      article.append(label, content)
      if (message.sources?.length) {
        const sources = document.createElement("div")
        sources.className = "ai-assistant__sources"
        for (const source of message.sources) {
          // Links são gerados no Rails; URLs externas e esquemas executáveis são rejeitados.
          if (typeof source.path !== "string" || !source.path.startsWith("/") || source.path.startsWith("//") || source.path.includes("\\")) continue
          const link = document.createElement("a")
          link.href = source.path
          link.textContent = source.label
          sources.append(link)
        }
        article.append(sources)
      }
      fragment.append(article)
    }
    this.messagesTarget.replaceChildren(fragment)
    this.messagesTarget.hidden = data.messages.length === 0
    this.welcomeTarget.hidden = data.messages.length > 0
    this.errorTarget.textContent = data.error || ""
    this.errorTarget.hidden = !data.error
    this.updateControls()
    if (atBottom) this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    if (this.processing) this.schedulePoll()
  }

  updateControls() {
    this.sendTarget.disabled = this.processing || this.requesting
    this.clearTarget.disabled = this.requesting
    this.statusTarget.hidden = !this.processing && !this.requesting
    this.statusTarget.textContent = this.processing ? "Consultando os registros…" : "Carregando…"
    this.messagesTarget.setAttribute("aria-busy", String(this.processing))
  }

  schedulePoll() {
    clearTimeout(this.pollTimer)
    if (this.alive && !this.panelTarget.hidden) this.pollTimer = setTimeout(() => this.load(), 2000)
  }

  showError(error) {
    if (!this.alive) return
    this.errorTarget.textContent = error.name === "AbortError" ? "A conexão demorou demais. Reabra o assistente para consultar a resposta." : error.message
    this.errorTarget.hidden = false
  }
}
