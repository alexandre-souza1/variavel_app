import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = []

  connect() {
    this.handleScan = (event) => this.scan(event.detail.file)
    window.addEventListener("invoice:scan", this.handleScan)
  }

  disconnect() {
    window.removeEventListener("invoice:scan", this.handleScan)
  }

  async scan(file) {
    if (!file) return this.showFlash("Selecione um arquivo primeiro.", "warning")

    const data = new FormData()
    data.append("document", file)
    const loadingFlash = this.showFlash("Lendo documento...", "info", true)
    const progressBar = loadingFlash?.querySelector(".progress-bar")
    if (progressBar) progressBar.style.width = "10%"
    this.progressTimer = setInterval(() => {
      const bar = loadingFlash?.querySelector(".progress-bar")
      if (!bar) return
      const current = parseInt(bar.style.width) || 10
      bar.style.width = `${Math.min(current + 5, 85)}%`
    }, 700)

    try {
      const response = await fetch("/invoices/scan_upload", {
        method: "POST",
        headers: { "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content, Accept: "application/json" },
        body: data
      })
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Falha na leitura")
      this.fillForm(result)
      if (progressBar) progressBar.style.width = "100%"
      loadingFlash?.remove()
      this.showFlash("Dados preenchidos. Confira antes de salvar.", "success")
    } catch (error) {
      loadingFlash?.remove()
      this.showFlash(error.message, "danger")
    } finally {
      clearInterval(this.progressTimer)
    }
  }

  fillForm(result) {
    this.setValue("invoice_date_issued", result.date_issued)
    this.setValue("invoice_total", result.total)
    const supplier = document.getElementById("invoice_supplier_id")
    if (supplier) {
      const option = [...supplier.options].find((item) => String(item.value) === String(result.supplier_id))
      if (option) {
        supplier.value = option.value
        supplier.dispatchEvent(new Event("change", { bubbles: true }))
      }
    }
    const invoices = result.invoices?.length ? result.invoices : [{ invoice_number: result.invoice_number, total: result.total }]
    const container = document.querySelector("[data-invoice-numbers-target='container']")
    const template = document.querySelector("[data-invoice-numbers-target='template']")
    container.querySelectorAll(".nested-fields[data-new-record='true']").forEach((row) => row.remove())
    invoices.forEach((invoice, index) => {
      if (index > 0) container.insertAdjacentHTML("beforeend", template.innerHTML.replace(/NEW_RECORD/g, Date.now() + index))
      const row = container.querySelectorAll(".nested-fields")[index]
      row.querySelector("input[name*='[number]']").value = invoice.invoice_number || ""
      row.querySelector("input[name*='[amount]']").value = invoice.total == null ? "" : Number(invoice.total).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
      const costCenterId = invoice.cost_center_id || (index === 0 ? result.cost_center_id : null)
      if (costCenterId) {
        const costCenter = row.querySelector("select[name*='[cost_center_id]']")
        if (costCenter) {
          costCenter.value = String(costCenterId)
          costCenter.dispatchEvent(new Event("change", { bubbles: true }))
        }
      }
    })
    document.querySelector("[data-controller='invoice-numbers']")?.querySelector("input[name*='[amount]']")?.dispatchEvent(new Event("input", { bubbles: true }))
  }

  setValue(id, value) { const field = document.getElementById(id); if (field && value != null) field.value = value }

  showFlash(message, type, withProgress = false) {
    const container = document.getElementById("flash-container")
    if (!container) return
    const alert = document.createElement("div")
    alert.className = `alert alert-${type} alert-dismissible fade show m-1`
    alert.setAttribute("role", "alert")
    alert.innerHTML = `${message}<button type="button" class="btn-close" aria-label="Fechar"></button>${withProgress ? '<div class="progress mt-2" style="height: 5px"><div class="progress-bar" style="width: 0%"></div></div>' : ''}`
    alert.querySelector(".btn-close").onclick = () => alert.remove()
    container.appendChild(alert)
    if (!withProgress) setTimeout(() => alert.remove(), 4000)
    return alert
  }
}
