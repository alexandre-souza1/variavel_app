import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["start", "stop", "submit", "file", "status", "timer", "panel"]
  static values = { maxDuration: Number, actionPlanId: Number }

  initialize() {
    this.chunks = []
    this.startedAt = null
    this.timerId = null
    this.submitting = false
    this.submitted = false
  }

  connect() {
    this.form = this.element.matches("form") ? this.element : this.element.querySelector("form")
    this.form?.addEventListener("turbo:submit-start", this.uploadStarted)
    this.form?.addEventListener("turbo:submit-end", this.uploadFinished)
    window.addEventListener("meeting-recorder:open", this.openFromEvent)
    document.addEventListener("turbo:before-visit", this.confirmLeavingActionPlan)
    window.addEventListener("beforeunload", this.confirmBeforeUnload)
  }

  disconnect() {
    window.removeEventListener("meeting-recorder:open", this.openFromEvent)
    this.form?.removeEventListener("turbo:submit-start", this.uploadStarted)
    this.form?.removeEventListener("turbo:submit-end", this.uploadFinished)
    document.removeEventListener("turbo:before-visit", this.confirmLeavingActionPlan)
    window.removeEventListener("beforeunload", this.confirmBeforeUnload)
  }

  openFromEvent = () => this.open()
  uploadStarted = () => {
    this.submitting = true
    this.startTarget.disabled = true
    this.setStatus("Enviando gravação. Aguarde a confirmação...")
  }

  uploadFinished = (event) => {
    this.submitting = false
    this.startTarget.disabled = false
    if (!event.detail.success) {
      this.submitted = false
      this.submitTarget.disabled = false
      this.setStatus("Não foi possível enviar. A gravação foi mantida; tente novamente.", true)
      this.open()
      return
    }

    this.submitted = true
    window.clearInterval(this.timerId)
    this.stream?.getTracks().forEach(track => track.stop())
    this.form.reset()
    this.fileTarget.value = ""
    this.chunks = []
    this.recorder = null
    this.stream = null
    this.startedAt = null
    this.timerId = null
    this.startTarget.classList.remove("d-none")
    this.stopTarget.classList.add("d-none")
    this.submitTarget.disabled = true
    this.timerTarget.textContent = "00:00"
    this.setStatus("Inicie quando todos estiverem prontos.")
    this.element.classList.remove("d-none")
    if (this.hasPanelTarget) this.close()
  }

  open() {
    if (this.submitted) {
      this.form?.reset()
      this.fileTarget.value = ""
      this.submitted = false
      this.submitting = false
      this.startTarget.classList.remove("d-none")
      this.stopTarget.classList.add("d-none")
      this.submitTarget.disabled = true
      this.timerTarget.textContent = "00:00"
      this.setStatus("Inicie quando todos estiverem prontos.")
    }

    this.element.classList.remove("d-none")
    this.element.classList.remove("is-collapsed")
    this.panelTarget.setAttribute("aria-hidden", "false")
  }

  close(event) {
    event?.preventDefault()
    this.element.classList.add("is-collapsed")
    this.panelTarget.setAttribute("aria-hidden", "true")
  }

  async start() {
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
      this.setStatus("Seu navegador não suporta gravação de áudio.", true)
      return
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      this.recorder = new MediaRecorder(this.stream)
      this.chunks = []
      this.submitted = false
      this.recorder.addEventListener("dataavailable", event => {
        if (event.data.size > 0) this.chunks.push(event.data)
      })
      this.recorder.addEventListener("stop", () => this.finishRecording())
      this.recorder.start()
      this.startedAt = Date.now()
      this.timerId = window.setInterval(() => this.updateTimer(), 1000)
      this.startTarget.classList.add("d-none")
      this.stopTarget.classList.remove("d-none")
      this.submitTarget.disabled = true
      this.setStatus("Gravando reunião...")
    } catch (error) {
      this.setStatus("Não foi possível acessar o microfone. Verifique a permissão do navegador.", true)
    }
  }

  stop() {
    if (!this.recorder || this.recorder.state === "inactive") return
    this.recorder.stop()
    this.stream?.getTracks().forEach(track => track.stop())
    window.clearInterval(this.timerId)
    this.stopTarget.classList.add("d-none")
    this.startTarget.classList.remove("d-none")
    this.setStatus("Processando gravação...")
  }

  confirmLeavingActionPlan = (event) => {
    if (!this.hasUnsubmittedRecording()) return

    const destination = new URL(event.detail.url, window.location.origin)
    if (this.belongsToActionPlan(destination)) return

    const confirmed = window.confirm("A gravação está em andamento. Se você sair deste action plan, a reunião será interrompida e a gravação será perdida. Deseja sair?")
    if (!confirmed) {
      event.preventDefault()
      return
    }

    this.discardRecording()
    this.element.removeAttribute("data-turbo-permanent")
  }

  confirmBeforeUnload = (event) => {
    if (!this.hasUnsubmittedRecording()) return

    event.preventDefault()
    event.returnValue = "A gravação será interrompida."
  }

  hasUnsubmittedRecording() {
    if (this.submitted) return false

    return this.recorder?.state === "recording" || this.fileTarget.files.length > 0
  }

  belongsToActionPlan(url) {
    return url.pathname.match(new RegExp(`^/action_plans/${this.actionPlanIdValue}(?:/|$)`))
  }

  discardRecording() {
    if (this.recorder && this.recorder.state !== "inactive") this.recorder.stop()
    this.stream?.getTracks().forEach(track => track.stop())
    window.clearInterval(this.timerId)
  }

  stopAtLimit() {
    if (!this.recorder || this.recorder.state === "inactive") return

    this.setStatus("Duração máxima atingida. Finalizando gravação...")
    this.stop()
  }

  finishRecording() {
    const mimeType = this.recorder.mimeType || "audio/webm"
    const extension = mimeType.includes("mp4") ? "mp4" : "webm"
    const blob = new Blob(this.chunks, { type: mimeType })
    const file = new File([blob], "reuniao-" + Date.now() + "." + extension, { type: mimeType })
    const transfer = new DataTransfer()
    transfer.items.add(file)
    this.fileTarget.files = transfer.files
    this.submitTarget.disabled = false
    this.setStatus("Gravação pronta. Revise os dados e gere a ata.")
  }

  updateTimer() {
    const elapsed = Math.floor((Date.now() - this.startedAt) / 1000)
    if (this.maxDurationValue > 0 && elapsed >= this.maxDurationValue * 60) {
      this.stopAtLimit()
      return
    }

    const minutes = String(Math.floor(elapsed / 60)).padStart(2, "0")
    const seconds = String(elapsed % 60).padStart(2, "0")
    this.timerTarget.textContent = minutes + ":" + seconds
  }

  setStatus(message, error = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("is-error", error)
  }
}
