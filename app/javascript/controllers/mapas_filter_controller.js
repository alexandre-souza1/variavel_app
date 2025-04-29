import { Controller } from "@hotwired/stimulus"

// Conecta com data-controller="mapas-filter"
export default class extends Controller {
  static targets = ["mapa", "motorista", "data", "ajudante", "mes", "ano", "row"]

  filter() {
    const mapa = this.mapaTarget.value.toLowerCase()
    const motorista = this.motoristaTarget.value.toLowerCase()
    const data = this.dataTarget.value.toLowerCase()
    const ajudante = this.ajudanteTarget.value.toLowerCase()
    const mes = this.mesTarget.value
    const ano = this.anoTarget.value

    this.rowTargets.forEach(row => {
      const cells = row.children
      const rowMapa = cells[0].textContent.toLowerCase()
      const rowData = cells[1].textContent.toLowerCase()
      const rowMotorista = cells[2].textContent.toLowerCase()
      const rowAjudante = cells[3].textContent.toLowerCase()

      // Obter o mês da data da linha (formato dd/mm/yyyy)
      const rowDataFormatted = cells[1].textContent.trim()
      const rowMonth = rowDataFormatted.split('/')[1] // Pega o mês (index 1)
      const rowYear = rowDataFormatted.split('/')[2] // Pega o mês (index 1)

      const matchMapa = rowMapa.includes(mapa)
      const matchData = rowData.includes(data)
      const matchMotorista = rowMotorista.includes(motorista)
      const matchAjudante = rowAjudante.includes(ajudante)
      const matchMes = mes ? rowMonth === mes : true // Verifica se o mês corresponde
      const matchAno = ano ? rowYear === ano : true // Verifica se o mês corresponde

      if (matchMapa && matchData && matchMotorista && matchAjudante && matchMes && matchAno) {
        row.style.display = ""
      } else {
        row.style.display = "none"
      }
    })
  }
}
