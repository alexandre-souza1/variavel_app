import { Controller } from "@hotwired/stimulus"
import { renderAssistantText } from "assistant_text"

export default class extends Controller {
  static targets = ["launcher", "panel", "messages", "welcome", "question", "send", "clear", "status", "error", "actionButton", "contextBar", "contextLabel", "contextButtons"]
  static values = { url: String, page: Object }

  connect() {
    this.alive = true
    this.processing = false
    this.requesting = false
    this.initialPage = this.pageValue
    this.renderContext()
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

  async startAutomation(event) {
    const question = typeof event?.detail?.question === "string" ? event.detail.question :
      "Quero criar uma nova automação. Me ajude a montar passo a passo, perguntando um dado por vez."
    await this.open()
    if (!this.alive) return
    if (!question.trim() || question.length > 2000) {
      this.showError(new Error("Descreva a automação em até 1800 caracteres."))
      return
    }
    this.questionTarget.value = question
    if (this.processing || this.requesting) {
      this.showError(new Error("Aguarde a resposta em andamento. Sua descrição ficou no campo de mensagem para enviar depois."))
      return
    }
    await this.send()
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
    this.pageValue = this.initialPage
    this.renderContext()
  }

  async request(method = "GET", body, path = this.urlValue) {
    if (!this.localPath(path)) throw new Error("Endereço de ação inválido.")
    this.abortController = new AbortController()
    const timeout = setTimeout(() => this.abortController?.abort(), 15000)
    try {
      const response = await fetch(path, {
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
    this.decisionError = null
    this.errorTarget.hidden = true
    this.updateControls()
    try {
      const data = await this.request("POST", { question, page_context: this.pageValue.reference || {} })
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
    if (!window.confirm("Limpar o histórico e cancelar as propostas pendentes? Os registros já criados ou alterados serão mantidos.")) return
    clearTimeout(this.pollTimer)
    this.requesting = true
    this.decisionError = null
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
    this.actions = new Map()
    for (const message of data.messages) {
      const article = document.createElement("article")
      article.className = `ai-assistant__message ai-assistant__message--${message.role === "user" ? "user" : "assistant"}`
      const label = document.createElement("small")
      label.textContent = message.role === "user" ? "Você" : "Assistente IA"
      const content = document.createElement(message.role === "user" ? "p" : "div")
      if (message.role === "user") content.textContent = message.content
      else {
        content.className = "ai-assistant__content"
        content.append(renderAssistantText(message.content))
      }
      article.append(label, content)
      if (message.sources?.length) {
        const sources = document.createElement("div")
        sources.className = "ai-assistant__sources"
        for (const source of message.sources) {
          // Links são gerados no Rails; URLs externas e esquemas executáveis são rejeitados.
          if (!this.localPath(source.path)) continue
          const link = document.createElement("a")
          link.href = source.path
          link.textContent = source.label
          sources.append(link)
        }
        article.append(sources)
      }
      for (const action of message.actions || []) {
        this.actions.set(String(action.id), action)
        article.append(this.renderAction(action))
      }
      fragment.append(article)
    }
    this.messagesTarget.replaceChildren(fragment)
    this.messagesTarget.hidden = data.messages.length === 0
    this.welcomeTarget.hidden = data.messages.length > 0
    if (this.decisionError && this.actions.get(this.decisionError.id)?.status !== "pending") this.decisionError = null
    const errorMessage = data.error || this.decisionError?.message || ""
    this.errorTarget.textContent = errorMessage
    this.errorTarget.hidden = !errorMessage
    this.updateControls()
    if (atBottom) this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    if (this.processing) this.schedulePoll()
  }

  updateControls() {
    this.sendTarget.disabled = this.processing || this.requesting
    this.clearTarget.disabled = this.requesting
    for (const button of this.actionButtonTargets) button.disabled = this.processing || this.requesting
    for (const button of this.contextButtonsTarget.querySelectorAll("button")) button.disabled = this.processing || this.requesting
    this.statusTarget.hidden = !this.processing && !this.requesting
    this.statusTarget.textContent = this.processing ? "Preparando sua resposta…" : "Carregando…"
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

  renderAction(action) {
    const card = document.createElement("section")
    card.className = "ai-assistant__proposal"
    card.dataset.actionId = action.id
    card.setAttribute("aria-label", action.preview.heading)
    const heading = document.createElement("small")
    heading.textContent = action.preview.heading
    const title = document.createElement("strong")
    title.textContent = action.preview.name
    card.append(heading, title)
    if (action.preview.description) card.append(this.paragraph(action.preview.description))
    if (!action.preview.changes?.length) card.append(this.details(action.preview.details))
    for (const change of action.preview.changes || []) {
      const comparison = document.createElement("div")
      comparison.className = "ai-assistant__change"
      const label = document.createElement("strong")
      label.textContent = change.label
      comparison.append(label, this.details([
        { label: "Antes", value: change.before }, { label: "Depois", value: change.after }
      ]))
      card.append(comparison)
    }
    if (action.preview.changes?.length) card.append(this.details(action.preview.details))
    for (const notice of action.preview.notices || []) card.append(this.paragraph(notice))
    for (const task of action.preview.tasks || []) {
      const item = document.createElement("div")
      item.className = "ai-assistant__proposal-task"
      const name = document.createElement("strong")
      name.textContent = task.title
      item.append(name)
      if (task.description) item.append(this.paragraph(task.description))
      item.append(this.details(task.details))
      if (task.checklist?.length) {
        const list = document.createElement("ul")
        list.setAttribute("aria-label", "Checklist")
        for (const content of task.checklist) {
          const li = document.createElement("li")
          li.textContent = content
          list.append(li)
        }
        item.append(list)
      }
      card.append(item)
    }
    const updating = action.kind === "update_task"
    const automation = action.kind === "create_automation"
    const status = this.paragraph((automation ? {
      pending: "Confira a regra e o estado de ativação. Ela só será salva ao confirmar. Esta proposta vale por 30 minutos.",
      executed: action.result?.enabled ? "Automação salva e ativada após sua confirmação." : "Automação salva pausada após sua confirmação.",
      cancelled: "Proposta cancelada. Nenhuma automação foi criada por esta proposta.",
      expired: "Proposta expirada. Peça uma nova ao assistente."
    } : updating ? {
      pending: "Confira as alterações. Elas só serão salvas ao confirmar. Esta proposta vale por 30 minutos.",
      executed: "Alterações salvas após sua confirmação.",
      cancelled: "Proposta cancelada. Nenhuma alteração foi aplicada por esta proposta.",
      expired: "Proposta expirada. Peça uma nova ao assistente."
    } : {
      pending: "Confira os dados. A criação só acontece ao confirmar. Esta proposta vale por 30 minutos.",
      executed: "Criação concluída após sua confirmação.",
      cancelled: "Proposta cancelada. Nenhum registro foi criado por esta proposta.",
      expired: "Proposta expirada. Peça uma nova ao assistente."
    })[action.status] || "Proposta indisponível.")
    status.className = "ai-assistant__proposal-status"
    status.setAttribute("role", "status")
    card.append(status)
    if (action.status === "pending") {
      const buttons = document.createElement("div")
      buttons.className = "ai-assistant__proposal-buttons"
      for (const [label, handler, style] of [
        [action.preview.confirmation_label || "Confirmar criação", "confirmAction", "btn-primary"],
        ["Ajustar", "adjustAction", "btn-outline-secondary"],
        ["Cancelar", "cancelAction", "btn-outline-secondary"]
      ]) {
        const button = document.createElement("button")
        button.type = "button"
        button.className = `btn btn-sm ${style}`
        button.textContent = label
        button.dataset.action = `ai-assistant#${handler}`
        button.dataset.aiAssistantTarget = "actionButton"
        button.dataset.id = action.id
        buttons.append(button)
      }
      card.append(buttons)
    }
    if (action.status === "executed" && this.localPath(action.result?.path)) {
      const link = document.createElement("a")
      link.href = action.result.path
      link.textContent = action.result.label
      link.className = "ai-assistant__proposal-result"
      card.append(link)
    }
    return card
  }

  details(fields = []) {
    const list = document.createElement("dl")
    for (const field of fields) {
      const label = document.createElement("dt")
      label.textContent = field.label
      const value = document.createElement("dd")
      value.textContent = field.value
      list.append(label, value)
    }
    return list
  }

  paragraph(text) {
    const paragraph = document.createElement("p")
    paragraph.textContent = text
    return paragraph
  }

  confirmAction(event) { this.decideAction(event, "confirm") }
  cancelAction(event) { this.decideAction(event, "cancel") }

  adjustAction(event) {
    const action = this.actions?.get(event.currentTarget.dataset.id)
    if (!action || this.processing || this.requesting) return
    this.questionTarget.value = `Quero ajustar a proposta "${action.preview.name}": `
    this.questionTarget.focus()
  }

  async decideAction(event, decision) {
    const action = this.actions?.get(event.currentTarget.dataset.id)
    if (!action || action.status !== "pending" || this.processing || this.requesting) return
    clearTimeout(this.pollTimer)
    this.requesting = true
    this.decisionError = null
    this.errorTarget.hidden = true
    this.updateControls()
    try {
      const data = await this.request("POST", { confirmation_token: action.confirmation_token }, action[`${decision}_path`])
      this.render(data)
      const decided = data.messages.flatMap(message => message.actions || []).find(item => String(item.id) === String(action.id))
      if (decided?.kind === "update_task" && decided.status === "executed") this.syncTaskContext(decided.result)
    } catch (error) {
      this.showError(error)
      this.decisionError = { id: String(action.id), message: this.errorTarget.textContent }
      // Fetch the authoritative state if a committed confirmation lost its response.
      this.schedulePoll()
    } finally {
      this.requesting = false
      if (this.alive) this.updateControls()
    }
  }

  localPath(path) {
    return typeof path === "string" && path.startsWith("/") && !path.startsWith("//") && !/[\\\s]/.test(path)
  }

  async openWithContext(event) {
    if (!event.detail?.page?.reference) return
    this.pageValue = event.detail.page
    this.renderContext()
    await this.open()
  }

  removeContext() {
    this.pageValue = {}
    this.renderContext()
  }

  renderContext() {
    this.contextBarTarget.hidden = !this.pageValue.reference
    this.contextLabelTarget.textContent = this.pageValue.label || ""
    this.contextButtonsTarget.replaceChildren()
    for (const shortcut of this.pageValue.shortcuts || []) {
      const button = document.createElement("button")
      button.type = "button"
      button.textContent = shortcut.label
      button.dataset.question = shortcut.question
      button.dataset.action = "ai-assistant#suggest"
      button.disabled = this.processing || this.requesting
      this.contextButtonsTarget.append(button)
    }
  }

  syncTaskContext(result) {
    if (this.pageValue.reference?.type !== "task" || String(this.pageValue.reference.id) !== String(result.id)) return
    this.pageValue = { ...this.pageValue, label: `Tarefa: ${result.title}`, shortcuts: [
      { label: "Resumir tarefa", question: "Resuma esta tarefa e seu prazo." },
      { label: "Alterar prazo", question: "Quero alterar o prazo desta tarefa." },
      result.completed ? { label: "Reabrir tarefa", question: "Prepare a reabertura desta tarefa." } : { label: "Concluir tarefa", question: "Prepare a conclusão desta tarefa." }
    ] }
    this.renderContext()
  }
};
