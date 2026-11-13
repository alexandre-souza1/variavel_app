import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "input"]

  connect() {
    this.files = Array.from(this.inputTarget.files)
    const types = Array.from(this.listTarget.querySelectorAll('[name="document_types[]"]'), (input) => input.value)
    this.types = this.files.map((file, index) => types[index] || "nf")
    this.renderFiles()
  }

  openFileDialog() {
    this.inputTarget.click()
  }

  handleFiles(event) {
    const newFiles = Array.from(event.target.files)

    this.files = this.files.concat(newFiles)
    this.types.push(...newFiles.map(() => "nf"))

    // limpa input original
    this.inputTarget.value = ""

    this.renderFiles()
    this.syncInputFiles()
  }

  removePendingDocument(event) {
    event.currentTarget.closest("[data-pending-document]").remove()
  }

  syncInputFiles() {
    const dataTransfer = new DataTransfer()

    this.files.forEach((file) => {
      dataTransfer.items.add(file)
    })

    this.inputTarget.files = dataTransfer.files
  }

  renderFiles() {
    this.listTarget.innerHTML = ""

    this.files.forEach((file, index) => {
      const container = document.createElement("div")

      container.className = "invoice-attachment"

      // 📄 Ícone
      const icon = document.createElement("div")
      icon.className = "invoice-attachment-icon"
      icon.innerHTML = file.type.includes("pdf")
        ? `<i class="bi bi-file-earmark-pdf" aria-hidden="true"></i>`
        : `<i class="bi bi-file-earmark" aria-hidden="true"></i>`

      // 📄 Nome
      const fileName = document.createElement("div")
      fileName.className = "invoice-attachment-name"
      fileName.innerText = file.name
      fileName.title = file.name

      // 🏷️ Tipo
      const hiddenType = document.createElement("input")
      hiddenType.type = "hidden"
      hiddenType.name = `document_types[]`
      hiddenType.value = this.types[index] || "nf"

      const typeBtn = document.createElement("button")
      typeBtn.type = "button"

      const setTypeVisual = () => {
        const labels = { nf: "Nota Fiscal", boleto: "Boleto", outro: "Outro" }
        typeBtn.title = `Tipo: ${labels[hiddenType.value]}. Clique para alterar.`
        if (hiddenType.value === "nf") {
          typeBtn.className = "icon-btn type-btn"
          typeBtn.innerHTML = `<i class="bi bi-receipt"></i>`
        } else if (hiddenType.value === "boleto") {
          typeBtn.className = "icon-btn type-btn warning"
          typeBtn.innerHTML = `<i class="bi bi-cash"></i>`
        } else {
          typeBtn.className = "icon-btn type-btn secondary"
          typeBtn.innerHTML = `<i class="bi bi-file-earmark"></i>`
        }
      }

      setTypeVisual()

      typeBtn.onclick = () => {
        if (hiddenType.value === "nf") hiddenType.value = "boleto"
        else if (hiddenType.value === "boleto") hiddenType.value = "outro"
        else hiddenType.value = "nf"

        this.types[index] = hiddenType.value
        setTypeVisual()
      }

      const scanBtn = document.createElement("button")
      scanBtn.type = "button"
      scanBtn.className = "icon-btn warning"
      scanBtn.title = "Ler NF com Textract"
      scanBtn.innerHTML = `<i class="bi bi-magic"></i>`
      scanBtn.onclick = () => {
        if (hiddenType.value === "nf") {
          window.dispatchEvent(new CustomEvent("invoice:scan", { detail: { file } }))
        }
      }

      // ❌ remover
      const removeBtn = document.createElement("button")
      removeBtn.type = "button"
      removeBtn.className = "icon-btn danger"
      removeBtn.title = "Remover anexo"
      removeBtn.innerHTML = `<i class="bi bi-trash3"></i>`

      removeBtn.onclick = () => {
        this.files.splice(index, 1)
        this.types.splice(index, 1)
        this.renderFiles()
        this.syncInputFiles()
      }

      container.appendChild(icon)
      container.appendChild(fileName)
      container.appendChild(typeBtn)
      container.appendChild(scanBtn)
      container.appendChild(removeBtn)
      container.appendChild(hiddenType)

      this.listTarget.appendChild(container)
    })
  }
}
