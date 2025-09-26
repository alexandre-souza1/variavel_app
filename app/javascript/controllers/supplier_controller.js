import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "cnpj",
    "name",
    "situation",
    "email",
    "phone",
    "street",
    "number",
    "complement",
    "neighborhood",
    "city",
    "state",
    "zipCode"
  ]

  // Método chamado quando o campo CNPJ perde o foco
  fetchSupplierData() {
    const cnpj = this.cnpjTarget.value.replace(/\D/g, "")

    if (cnpj.length !== 14) {
      this.showAlert("CNPJ inválido. Deve conter 14 dígitos.", "warning")
      return
    }

    // Mostra loading
    this.setLoading(true)

    fetch(`/suppliers/search_cnpj?cnpj=${cnpj}`)
      .then(res => {
        if (!res.ok) throw new Error(`Erro na requisição: ${res.status}`)
        return res.json()
      })
      .then(data => {
        if (data.error) {
          throw new Error(data.error)
        }

        this.fillFormFields(data)
        this.showAlert("Dados do CNPJ carregados com sucesso!", "success")
      })
      .catch(err => {
        console.error("Erro ao buscar CNPJ:", err)
        this.showAlert(`Erro: ${err.message}`, "error")
        this.clearFormFields()
      })
      .finally(() => {
        this.setLoading(false)
      })
  }

  // Preenche todos os campos do formulário
  fillFormFields(data) {
    this.nameTarget.value = data.name || ""
    this.situationTarget.value = data.situation || ""
    this.emailTarget.value = data.email || ""
    this.phoneTarget.value = data.phone || ""
    this.streetTarget.value = data.street || ""
    this.numberTarget.value = data.number || ""
    this.complementTarget.value = data.complement || ""
    this.neighborhoodTarget.value = data.neighborhood || ""
    this.cityTarget.value = data.city || ""
    this.stateTarget.value = data.state || ""
    this.zipCodeTarget.value = data.zip_code || ""
  }

  // Limpa todos os campos (exceto CNPJ)
  clearFields() {
    this.cnpjTarget.value = ""
    this.clearFormFields()
    this.showAlert("Campos limpos com sucesso!", "info")
  }

  // Limpa apenas os campos de dados (mantém o CNPJ)
  clearFormFields() {
    this.nameTarget.value = ""
    this.situationTarget.value = ""
    this.emailTarget.value = ""
    this.phoneTarget.value = ""
    this.streetTarget.value = ""
    this.numberTarget.value = ""
    this.complementTarget.value = ""
    this.neighborhoodTarget.value = ""
    this.cityTarget.value = ""
    this.stateTarget.value = ""
    this.zipCodeTarget.value = ""
  }

  // Mostra mensagens de alerta
  showAlert(message, type = "info") {
    // Remove alertas anteriores
    const existingAlert = this.element.querySelector('.alert')
    if (existingAlert) {
      existingAlert.remove()
    }

    // Cria novo alerta
    const alertDiv = document.createElement('div')
    alertDiv.className = `alert alert-${this.getAlertClass(type)} alert-dismissible fade show mt-3`
    alertDiv.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `

    this.element.insertBefore(alertDiv, this.element.firstChild)

    // Auto-remove após 5 segundos
    setTimeout(() => {
      if (alertDiv.parentNode) {
        alertDiv.remove()
      }
    }, 5000)
  }

  getAlertClass(type) {
    const classes = {
      success: 'success',
      error: 'danger',
      warning: 'warning',
      info: 'info'
    }
    return classes[type] || 'info'
  }

  // Controla estado de loading
  setLoading(loading) {
    const button = this.element.querySelector('input[type="submit"]')
    if (button) {
      if (loading) {
        button.value = "Buscando..."
        button.disabled = true
      } else {
        button.value = "Salvar"
        button.disabled = false
      }
    }
  }
}
