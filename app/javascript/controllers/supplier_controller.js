import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cnpj", "name", "fantasyName", "situation", "email", "phone", "street", "number",
    "complement", "neighborhood", "city", "state", "zipCode", "status", "lookupButton", "lookupLabel", "submit",
    "editableField", "editButton", "editLabel", "editHint"]

  connect() {
    if (this.nameTarget.value) {
      this.lastLookup = this.cnpjTarget.value.replace(/\D/g, "")
      this.showAlert("Consulte para atualizar os dados cadastrais.")
    }
  }

  disconnect() {
    this.request?.abort()
  }

  lookupOnEnter(event) {
    event.preventDefault()
    this.fetchSupplierData(event)
  }

  async fetchSupplierData(event) {
    const cnpj = this.cnpjTarget.value.replace(/\D/g, "")
    if (!cnpj && event?.type === "blur") return
    if (cnpj.length !== 14) {
      this.showAlert("Informe um CNPJ com 14 dígitos.", "warning")
      return
    }
    if (this.loading && this.requestCnpj === cnpj) return
    if (event?.type === "blur" && this.lastLookup === cnpj) return

    this.request?.abort()
    const request = new AbortController()
    this.request = request
    this.requestCnpj = cnpj
    this.setLoading(true)
    this.showAlert("Consultando os dados do CNPJ…", "loading")

    try {
      const response = await fetch(`/suppliers/search_cnpj?cnpj=${cnpj}`, { signal: request.signal })
      const data = await response.json()
      if (!response.ok || data.error || !data.name) throw new Error(data.error || "Não foi possível consultar este CNPJ. Tente novamente.")
      this.fillFormFields(data)
      this.setManualEditing(false)
      this.lastLookup = cnpj
      this.showAlert("Dados cadastrais preenchidos.", "success")
    } catch (error) {
      if (error.name === "AbortError") return
      this.clearFormFields()
      this.lastLookup = null
      this.showAlert(error instanceof TypeError ? "Não foi possível consultar o CNPJ. Verifique a conexão e tente novamente." : error.message, "error")
    } finally {
      if (this.request === request) this.setLoading(false)
    }
  }

  fillFormFields(data) {
    const keys = { fantasyName: "fantasy_name", zipCode: "zip_code" }
    for (const target of ["name", "fantasyName", "situation", "email", "phone", "street", "number", "complement", "neighborhood", "city", "state", "zipCode"]) {
      this[`${target}Target`].value = data[keys[target] || target] || ""
    }
  }

  clearFields() {
    this.request?.abort()
    this.request = null
    this.lastLookup = null
    this.setLoading(false)
    this.cnpjTarget.value = ""
    this.clearFormFields()
    this.setManualEditing(false)
    this.showAlert("Campos limpos. Informe um CNPJ para consultar.")
    this.cnpjTarget.focus()
  }

  clearFormFields() {
    this.fillFormFields({})
  }

  showAlert(message, type = "info") {
    this.statusTarget.textContent = message
    this.statusTarget.dataset.state = type
  }

  toggleManualEditing() {
    this.setManualEditing(this.editButtonTarget.getAttribute("aria-pressed") !== "true")
  }

  setManualEditing(editing) {
    this.editableFieldTargets.forEach(field => { field.readOnly = !editing })
    this.editButtonTarget.setAttribute("aria-pressed", String(editing))
    this.editLabelTarget.textContent = editing ? "Concluir edição" : "Editar dados"
    this.editHintTarget.textContent = editing
      ? "Edição manual liberada. Salve para aplicar as alterações."
      : "Os dados abaixo são preenchidos pela consulta do CNPJ."
  }

  setLoading(loading) {
    this.loading = loading
    this.element.setAttribute("aria-busy", String(loading))
    this.lookupButtonTarget.disabled = loading
    this.lookupLabelTarget.textContent = loading ? "Consultando…" : "Consultar"
    this.submitTarget.disabled = loading
    this.editButtonTarget.disabled = loading
  }
}
