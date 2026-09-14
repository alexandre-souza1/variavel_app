import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["start", "stop", "submit", "file", "status", "timer"]
  static values = { maxDuration: Number }

  connect() {
    this.chunks = []
    this.startedAt = null
    this.timerId = null
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
