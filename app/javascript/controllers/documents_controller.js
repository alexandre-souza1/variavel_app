import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "input"]

  connect() {
    this.files = []
  }

  openFileDialog() {
    this.inputTarget.click()
  }

  handleFiles(event) {
    const newFiles = Array.from(event.target.files)

    this.files = this.files.concat(newFiles)

    // limpa input original
    this.inputTarget.value = ""

    this.renderFiles()
    this.syncInputFiles()
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

      container.classList.add(
        "border",
        "rounded",
        "p-2",
        "text-center",
        "bg-white",
        "shadow-sm",
        "position-relative"
      )

      container.style.fontSize = "0.75rem"

      // 📄 Ícone
      const icon = document.createElement("div")
      icon.innerHTML = file.type.includes("pdf")
        ? `<i class="bi bi-file-earmark-pdf text-danger" style="font-size: 1.8rem;"></i>`
        : `<i class="bi bi-file-earmark text-secondary" style="font-size: 1.8rem;"></i>`

      // 📄 Nome
      const fileName = document.createElement("div")
      fileName.innerText = file.name
      fileName.style.wordBreak = "break-word"
      fileName.style.maxWidth = "220px"
      fileName.style.whiteSpace = "nowrap"
      fileName.style.overflow = "hidden"
      fileName.style.textOverflow = "ellipsis"

      // 🏷️ Tipo
      const hiddenType = document.createElement("input")
      hiddenType.type = "hidden"
      hiddenType.name = `document_types[]`
      hiddenType.value = "nf"

      const typeBtn = document.createElement("button")
      typeBtn.type = "button"

      const setTypeVisual = () => {
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
        this.renderFiles()
        this.syncInputFiles()
      }

      container.appendChild(removeBtn)
      container.appendChild(icon)
      container.appendChild(fileName)
      container.appendChild(typeBtn)
      container.appendChild(scanBtn)
      container.appendChild(hiddenType)

      this.listTarget.appendChild(container)
    })
  }
}
