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

      container.style.width = "120px"
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

      // 🏷️ Tipo
      const hiddenType = document.createElement("input")
      hiddenType.type = "hidden"
      hiddenType.name = `document_types[]`
      hiddenType.value = "nf"

      const typeBtn = document.createElement("button")
      typeBtn.type = "button"

      const setTypeVisual = () => {
        if (hiddenType.value === "nf") {
          typeBtn.className = "btn btn-sm btn-outline-primary mt-1"
          typeBtn.innerHTML = `<i class="bi bi-receipt me-1"></i> NF`
        } else if (hiddenType.value === "boleto") {
          typeBtn.className = "btn btn-sm btn-outline-warning mt-1"
          typeBtn.innerHTML = `<i class="bi bi-cash me-1"></i> Boleto`
        } else {
          typeBtn.className = "btn btn-sm btn-outline-secondary mt-1"
          typeBtn.innerHTML = `<i class="bi bi-file-earmark me-1"></i> Outro`
        }
      }

      setTypeVisual()

      typeBtn.onclick = () => {
        if (hiddenType.value === "nf") hiddenType.value = "boleto"
        else if (hiddenType.value === "boleto") hiddenType.value = "outro"
        else hiddenType.value = "nf"

        setTypeVisual()
      }

      // ❌ remover
      const removeBtn = document.createElement("button")
      removeBtn.type = "button"
      removeBtn.className = "btn btn-sm btn-light border position-absolute"
      removeBtn.style.top = "2px"
      removeBtn.style.right = "2px"
      removeBtn.innerHTML = `<i class="bi bi-x-lg text-danger"></i>`

      removeBtn.onclick = () => {
        this.files.splice(index, 1)
        this.renderFiles()
        this.syncInputFiles()
      }

      container.appendChild(removeBtn)
      container.appendChild(icon)
      container.appendChild(fileName)
      container.appendChild(typeBtn)
      container.appendChild(hiddenType)

      this.listTarget.appendChild(container)
    })
  }
}
