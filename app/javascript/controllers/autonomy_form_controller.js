import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["registration", "equipmentType", "serviceType", "plate"]

  connect() {
    // Inicializa os selects vazios
    this.updateServiceTypes([])
    this.updatePlates([])
  }

  async checkRegistration() {
    const registration = this.registrationTarget.value.trim()
    if (registration.length === 0) return

    try {
      const response = await fetch(`/autonomies/check_registration?registration=${registration}`)
      const data = await response.json()

      if (data.user_type === 'Driver') {
        this.updateEquipmentTypes(['Caminhão'])
      } else if (data.user_type === 'Operator') {
        this.updateEquipmentTypes(['Empilhadeira', 'Máquina de Limpeza', 'Paleteira'])
      } else {
        this.updateEquipmentTypes(['Empilhadeira', 'Máquina de Limpeza', 'Paleteira', 'Caminhão'])
      }
    } catch (error) {
      console.error("Error checking registration:", error)
    }
  }

  updateEquipmentTypes(types) {
    const select = this.equipmentTypeTarget
    const currentValue = select.value

    // Limpa as opções atuais
    while (select.options.length > 0) {
      select.remove(0)
    }

    // Adiciona o prompt
    const defaultOption = new Option("Selecione", "")
    select.add(defaultOption)

    // Adiciona as novas opções
    types.forEach(type => {
      const option = new Option(type, type)
      select.add(option)
    })

    // Restaura o valor anterior se ainda estiver disponível
    if (types.includes(currentValue)) {
      select.value = currentValue
    }

    // Dispara o evento change para atualizar os serviços e placas
    this.updateServiceTypesAndPlates()
  }

  async updateServiceTypesAndPlates() {
    const equipmentType = this.equipmentTypeTarget.value

    // Atualiza os tipos de serviço baseados no tipo de equipamento
    let serviceTypes = []
    if (equipmentType === 'Caminhão') {
      serviceTypes = ['Inspeção de Cabo de Aço', 'Inspeção de Plataforma']
    } else if (equipmentType === 'Empilhadeira') {
      serviceTypes = ['Limpeza Profunda', 'Inspeção Técnica', '5s']
    } else if (equipmentType === 'Máquina de Limpeza') {
      serviceTypes = ['Limpeza Profunda', 'Inspeção Técnica', '5s']
    } else if (equipmentType === 'Paleteira') {
      serviceTypes = ['Limpeza Profunda', 'Inspeção Técnica', '5s']
    }
    this.updateServiceTypes(serviceTypes)

    // Busca as placas correspondentes ao tipo de equipamento
    if (equipmentType) {
      try {
        const response = await fetch(`/autonomies/plates?equipment_type=${encodeURIComponent(equipmentType)}`)
        const plates = await response.json()
        this.updatePlates(plates)
      } catch (error) {
        console.error("Error fetching plates:", error)
        this.updatePlates([])
      }
    } else {
      this.updatePlates([])
    }
  }

  updateServiceTypes(types) {
    const select = this.serviceTypeTarget
    const currentValue = select.value

    // Limpa as opções atuais
    while (select.options.length > 0) {
      select.remove(0)
    }

    // Adiciona o prompt
    const defaultOption = new Option("Selecione", "")
    select.add(defaultOption)

    // Adiciona as novas opções
    types.forEach(type => {
      const option = new Option(type, type)
      select.add(option)
    })

    // Restaura o valor anterior se ainda estiver disponível
    if (types.includes(currentValue)) {
      select.value = currentValue
    }
  }

  updatePlates(plates) {
    const select = this.plateTarget
    const currentValue = select.value

    // Limpa as opções atuais
    while (select.options.length > 0) {
      select.remove(0)
    }

    // Adiciona o prompt
    const defaultOption = new Option("Selecione a placa", "")
    select.add(defaultOption)

    // Adiciona as novas opções
    plates.forEach(plate => {
      const option = new Option(plate, plate)
      select.add(option)
    })

    // Restaura o valor anterior se ainda estiver disponível
    if (plates.includes(currentValue)) {
      select.value = currentValue
    }
  }

  validate(event) {
    const form = event.target
    if (!form.checkValidity()) {
      event.preventDefault()
      event.stopPropagation()
    }
    form.classList.add('was-validated')
  }
}
