import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "preview",
    "descriptionContainer",
    "kind",
    "video",
    "canvas",
    "input",
    "captureButton"
  ]

  connect() {
    this.toggleDescription()
  }

  preview(event) {
    const file = event.target.files[0]

    if (!file) return

    const reader = new FileReader()

    reader.onload = (e) => {
      this.previewTarget.src = e.target.result
      this.previewTarget.classList.remove("d-none")
    }

    reader.readAsDataURL(file)
  }

  toggleDescription() {
    const isDefect =
      this.kindTarget.value === "defect"

    this.descriptionContainerTarget
      .classList.toggle("d-none", !isDefect)
  }

  async openCamera(event) {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: {
            ideal: "environment"
          }
        },
        audio: false
      })

      this.videoTarget.srcObject = stream

      this.videoTarget.classList.remove("d-none")
      this.captureButtonTarget.classList.remove("d-none")

    } catch (error) {
      console.error(error)
      alert("Não foi possível acessar a câmera")
    }
  }

  takePhoto() {
    const context = this.canvasTarget.getContext("2d")

    this.canvasTarget.width = this.videoTarget.videoWidth
    this.canvasTarget.height = this.videoTarget.videoHeight

    context.drawImage(
      this.videoTarget,
      0,
      0
    )

    this.canvasTarget.toBlob((blob) => {

      const file = new File(
        [blob],
        `photo-${Date.now()}.jpg`,
        {
          type: "image/jpeg"
        }
      )

      const dataTransfer = new DataTransfer()

      dataTransfer.items.add(file)

      this.inputTarget.files = dataTransfer.files

      this.previewTarget.src =
        URL.createObjectURL(blob)

      this.previewTarget.classList.remove("d-none")

      const stream =
        this.videoTarget.srcObject

      stream.getTracks().forEach(track => track.stop())

      this.videoTarget.classList.add("d-none")
      this.captureButtonTarget.classList.add("d-none")

    }, "image/jpeg", 0.9)
  }
}