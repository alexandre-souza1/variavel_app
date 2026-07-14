import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mapa", "motorista", "data", "ajudante", "mes", "ano", "row", "folder"]

  filter() {
    const mapa = this.mapaTarget.value.toLowerCase()
    const motorista = this.motoristaTarget.value.toLowerCase()
    const data = this.dataTarget.value.toLowerCase()
    const ajudante = this.ajudanteTarget.value.toLowerCase()
    const mes = this.mesTarget.value
    const ano = this.anoTarget.value

    // Verifica se há algum filtro ativo (para decidir se forçamos a abertura das pastas)
    const hasFilter = mapa || motorista || data || ajudante || mes || ano

    // 1. Filtrar as linhas
    this.rowTargets.forEach(row => {
      const cells = row.children
      const rowMapa = cells[1].textContent.toLowerCase()
      const rowData = cells[2].textContent.toLowerCase()
      const rowMotorista = cells[3].textContent.toLowerCase()
      const rowAjudante = cells[4].textContent.toLowerCase()

      const rowDataFormatted = cells[2].textContent.trim()
      const rowMonth = rowDataFormatted.split('/')[1] // mm
      const rowYear = rowDataFormatted.split('/')[2] // yyyy

      const matchMapa = rowMapa.includes(mapa)
      const matchData = rowData.includes(data)
      const matchMotorista = rowMotorista.includes(motorista)
      const matchAjudante = rowAjudante.includes(ajudante)
      const matchMes = mes ? rowMonth === mes : true
      const matchAno = ano ? rowYear === ano : true

      row.style.display = (matchMapa && matchData && matchMotorista && matchAjudante && matchMes && matchAno) ? "" : "none"
    })

    // 2. Processar pastas: ocultar as vazias e abrir as que têm resultados (se houver filtro)
    this.folderTargets.forEach(folder => {
      const rows = folder.querySelectorAll('[data-mapas-filter-target="row"]')
      const hasVisible = Array.from(rows).some(row => row.style.display !== "none")

      if (!hasVisible) {
        folder.style.display = "none"
      } else {
        folder.style.display = ""
        // Se houver filtro ativo, abrir a pasta (expandir o collapse)
        if (hasFilter) {
          const collapse = folder.querySelector('.accordion-collapse')
          const button = folder.querySelector('.accordion-button')
          if (collapse && button) {
            collapse.classList.add('show')
            button.classList.remove('collapsed')
            button.setAttribute('aria-expanded', 'true')
          }
        }
      }
    })
  }
}
