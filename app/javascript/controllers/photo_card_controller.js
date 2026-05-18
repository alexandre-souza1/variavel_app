import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "preview",
    "descriptionContainer",
    "kind",
    "video",
    "canvas",
    "input",
    "captureButton",
    "pickButton",
    "replaceActions",
    "destroyInput"
  ]

  connect() {
    this.toggleDescription()
    this.syncPhotoActions()
  }

  preview(event) {
    const file = event.target.files[0]

    if (!file) return

    const reader = new FileReader()

    reader.onload = (e) => {
      this.previewTarget.src = e.target.result
      this.previewTarget.classList.remove("d-none")
      this.keepPhoto()
      this.syncPhotoActions()
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
      this.keepPhoto()
      this.syncPhotoActions()

      const stream =
        this.videoTarget.srcObject

      stream.getTracks().forEach(track => track.stop())

      this.videoTarget.classList.add("d-none")
      this.captureButtonTarget.classList.add("d-none")

    }, "image/jpeg", 0.9)
  }

  openFilePicker() {
    this.inputTarget.click()
  }

  clearPhoto() {
    this.inputTarget.value = ""

    if (this.hasDestroyInputTarget) {
      this.destroyInputTarget.value = "1"
    }

    this.previewTarget.src = ""
    this.previewTarget.classList.add("d-none")
    this.syncPhotoActions()
  }

  keepPhoto() {
    if (this.hasDestroyInputTarget) {
      this.destroyInputTarget.value = "false"
    }
  }

  syncPhotoActions() {
    const hasPhoto =
      this.previewTarget.src.length > 0 &&
      !this.previewTarget.classList.contains("d-none")

    if (this.hasPickButtonTarget) {
      this.pickButtonTarget.classList.toggle("d-none", hasPhoto)
    }

    if (this.hasReplaceActionsTarget) {
      this.replaceActionsTarget.classList.toggle("d-none", !hasPhoto)
    }
  }
}
