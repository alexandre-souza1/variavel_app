import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["drop", "person", "message", "reason", "save", "dirty", "driverCount", "driverGap", "helperGap", "carCount", "shortageSummary", "dialog", "error", "routingForm", "routingButton", "routingReport"]
  static values = { state: Object, editable: Boolean, url: String, importUrl: String, plateOptions: Array, date: String, revision: Number, signature: String, filterRole: String, filterGroup: String }

  connect() {
    this.original = structuredClone(this.stateValue)
    this.state = structuredClone(this.original)
    this.sortables = []
    this.selected = null
    this.changed = false
    this.saving = false
    if (!this.editableValue) return
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.beforeUnload = event => { if (this.changed) { event.preventDefault(); event.returnValue = "" } }
    this.beforeVisit = event => { if (this.changed && !confirm("Descartar as alterações ainda não salvas do painel?")) event.preventDefault() }
    window.addEventListener("beforeunload", this.beforeUnload)
    document.addEventListener("turbo:before-visit", this.beforeVisit)
    this.draw()
  }

  disconnect() {
    this.sortables.forEach(sortable => sortable.destroy())
    this.abortController?.abort()
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
    window.removeEventListener("beforeunload", this.beforeUnload)
    document.removeEventListener("turbo:before-visit", this.beforeVisit)
  }

  member(id) { return this.state.members.find(member => String(member.id) === String(id)) }
  car(key) { return this.state.cars.find(car => car.key === key) }
  matchesFilter(member) {
    return (!this.filterRoleValue || member.membership_role === this.filterRoleValue) &&
      (!this.filterGroupValue || member.group === this.filterGroupValue)
  }

  select(event) {
    event.stopPropagation()
    if (!this.editableValue || this.saving || this.importing) return
    const id = event.currentTarget.closest(".time-off-chip").dataset.memberId
    if (this.member(id)?.vacation) return
    const destination = event.currentTarget.closest('[data-car][data-role]')
    if (this.selected && this.selected !== id && destination) { this.move(this.selected, destination.dataset); return }
    this.selected = this.selected === id ? null : id
    this.draw()
    this.announce(this.selected ? `Selecionado: ${this.member(id).name}. Toque na vaga ou na lista de destino.` : "Seleção cancelada.")
  }

  destination(event) {
    event.stopPropagation()
    if (!this.selected || this.saving || this.importing) return
    const drop = event.currentTarget.closest("[data-time-off-board-target='drop']")
    if (event.target.closest('.time-off-chip') && !drop?.dataset.car) return
    if (drop) this.move(this.selected, drop.dataset)
  }

  release(event) {
    event.stopPropagation()
    if (!this.editableValue || this.saving || this.importing) return
    this.move(event.currentTarget.closest(".time-off-chip").dataset.memberId, { status: "working" })
  }

  clearSelection() {
    if (this.saving) return
    this.selected = null
    this.draw()
    this.announce("Seleção cancelada; o rascunho foi mantido.")
  }

  move(id, destination) {
    const member = this.member(id)
    if (!member || !member.active || member.vacation || member.status === "pending" || this.saving || this.importing) { this.draw(); return }
    const car = destination.car ? this.car(destination.car) : null
    if (car) {
      if (!car.scheduled || !["driver", "helper1", "helper2"].includes(destination.role) ||
          (destination.role !== "driver" && Number(destination.role.slice(-1)) > car.helper_count)) { this.draw(); return }
      const driver = destination.role === "driver"
      const valid = driver ? member.cargo === (car.operation === "van" ? "van" : "motorista") : ["ajudante", "motorista", "van"].includes(member.cargo)
      if (!valid) {
        this.selected = null
        this.draw()
        this.announce(car.operation === "van" && driver ? "Esta vaga exige o cargo Motorista de van." : "Ajudante não pode assumir motorista. Escolha uma função compatível.", true)
        return
      }
    } else if (!["working", "off", "unavailable"].includes(destination.status)) { this.draw(); return }
    this.state.cars.forEach(slot => ["driver", "helper1", "helper2"].forEach(role => { if (String(slot[role]) === String(id)) slot[role] = null }))
    if (car) {
      car[destination.role] = member.id
      member.status = "working"
    } else member.status = destination.status
    this.selected = null
    this.changed = JSON.stringify(this.state) !== JSON.stringify(this.original)
    this.draw()
    this.announce(`${member.name}: alteração no rascunho. Salve o painel para confirmar.`)
  }

  composition(event) {
    if (!this.editableValue || this.saving || this.importing) return
    const car = this.car(event.currentTarget.dataset.car)
    car.helper_count = Number(event.currentTarget.value)
    if (car.helper_count < 2) car.helper2 = null
    if (car.helper_count < 1) car.helper1 = null
    this.changed = JSON.stringify(this.state) !== JSON.stringify(this.original)
    this.draw()
    this.announce("Composição ajustada no rascunho. Nomes retirados voltaram para Disponíveis.")
  }

  scheduled(event) {
    if (!this.editableValue || this.saving || this.importing) return
    const car = this.car(event.currentTarget.dataset.car)
    car.scheduled = event.currentTarget.checked
    if (!car.scheduled) ["driver", "helper1", "helper2"].forEach(role => { car[role] = null })
    this.changed = JSON.stringify(this.state) !== JSON.stringify(this.original)
    this.draw()
    this.announce(car.scheduled ? "Saída prevista. Complete a equipe e salve." : "Sem saída neste dia. A equipe voltou para Disponíveis; isso não registra folga.")
  }

  plate(event) {
    if (!this.editableValue || this.saving || this.importing) return
    const car = this.car(event.currentTarget.dataset.car)
    const plate = event.currentTarget.value || null
    if (plate && car.scheduled && this.state.cars.some(other => other.key !== car.key && other.scheduled && other.plate === plate)) {
      this.draw()
      this.announce("Esta placa já está em outra saída. Libere a placa antes de transferi-la.", true)
      return
    }
    car.plate = plate
    this.changed = JSON.stringify(this.state) !== JSON.stringify(this.original)
    this.draw()
    this.announce("Placa ajustada no rascunho. Salve o painel para confirmar.")
  }

  async importRouting(event) {
    event.preventDefault()
    if (!this.editableValue || this.saving || this.importing || !this.routingFormTarget.reportValidity()) return
    this.importing = true
    this.routingButtonTarget.disabled = true
    this.abortController = new AbortController()
    try {
      const response = await fetch(this.importUrlValue, {
        method: "POST", body: new FormData(this.routingFormTarget), credentials: "same-origin", signal: this.abortController.signal,
        headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      })
      if (response.redirected) throw new Error("Sua sessão expirou. Atualize a página para entrar novamente.")
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Não foi possível importar o CSV.")
      const assignments = new Map(result.assignments.map(row => [row.key, row.plate]))
      this.state.routing_import = result.metadata
      this.state.routing_token = result.token
      this.state.cars.forEach(car => {
        if (assignments.has(car.key)) { car.plate = assignments.get(car.key); car.scheduled = true }
        else if (car.operation === "route") { car.plate = null; car.scheduled = false }
        if (!car.scheduled) ["driver", "helper1", "helper2"].forEach(role => { car[role] = null })
      })
      this.changed = true
      this.draw()
      this.announce("CSV carregado no rascunho. Revise as placas e as operações especiais antes de salvar.")
    } catch (error) {
      if (error.name !== "AbortError") this.announce(error.message === "Failed to fetch" ? "Falha de conexão. O rascunho foi mantido." : error.message, true)
    } finally {
      this.importing = false
      if (this.hasRoutingButtonTarget) this.routingButtonTarget.disabled = false
    }
  }

  reset() {
    if (this.saving || this.importing || !this.editableValue) return
    this.state = structuredClone(this.original)
    this.changed = false
    this.selected = null
    this.reasonTarget.value = ""
    this.draw()
    this.announce("Rascunho desfeito. Nenhuma alteração foi salva.")
  }

  chip(member, assigned) {
    const template = this.personTargets.find(person => person.dataset.memberId === String(member.id))
    const chip = template.content.firstElementChild.cloneNode(true)
    const button = chip.querySelector(".time-off-chip-select")
    button.setAttribute("aria-pressed", String(this.selected === String(member.id)))
    button.disabled = !member.active || member.vacation || member.status === "pending"
    chip.classList.toggle("is-selected", this.selected === String(member.id))
    const remove = chip.querySelector(".time-off-chip-remove")
    if (remove) remove.hidden = !assigned
    return chip
  }

  draw() {
    this.element.classList.toggle('has-selection', Boolean(this.selected))
    this.sortables.forEach(sortable => sortable.destroy())
    this.sortables = []
    const used = new Set(this.state.cars.flatMap(car => [car.driver, car.helper1, car.helper2]).filter(Boolean))
    this.dropTargets.forEach(drop => {
      drop.querySelectorAll(".time-off-chip").forEach(chip => chip.remove())
      let members
      if (drop.dataset.car) {
        const car = this.car(drop.dataset.car)
        const role = drop.dataset.role
        const position = drop.closest(".time-off-car-position")
        const required = car.scheduled !== false && (role === "driver" || Number(role.slice(-1)) <= car.helper_count)
        const member = this.member(car[role])
        if (position.classList.contains("time-off-day-position")) {
          drop.hidden = !required
          position.querySelector(".time-off-position-unused").hidden = required
          position.classList.toggle("is-empty", required && !member)
        } else position.hidden = !required
        members = required && member ? [member] : []
        if (!required) return
      } else members = this.state.members.filter(member => !used.has(member.id) && (member.vacation ? "unavailable" : member.status) === drop.dataset.status && this.matchesFilter(member))
      members.forEach(member => drop.insertBefore(this.chip(member, Boolean(drop.dataset.car)), drop.querySelector('.time-off-vacancy, .time-off-pool-placeholder')))
      const count = this.element.querySelector(`[data-pool-count="${drop.dataset.status}"]`)
      if (count) count.textContent = String(members.length)
      const summary = this.element.querySelector(`[data-pool-summary="${drop.dataset.status}"]`)
      if (summary) summary.textContent = `${members.filter(member => member.membership_role === "driver").length} motoristas · ${members.filter(member => member.membership_role === "helper").length} ajudantes`
      if (drop.dataset.status === "pending") return
      this.sortables.push(Sortable.create(drop, {
        group: "time-off-crews", draggable: '.time-off-chip[data-movable="true"]', sort: false,
        animation: matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 120,
        forceFallback: true, fallbackOnBody: true, fallbackTolerance: 3, emptyInsertThreshold: 15,
        filter: ".time-off-chip-remove", preventOnFilter: false, delay: 150, delayOnTouchOnly: true,
        ghostClass: "time-off-person--ghost",
        onEnd: event => { if (event.from === event.to) this.draw(); else this.move(event.item.dataset.memberId, event.to.dataset) }
      }))
    })
    this.state.cars.forEach(car => {
      const select = this.element.querySelector(`select[data-car="${car.key}"][data-action*="#composition"]`)
      if (select) { select.value = String(car.helper_count); select.disabled = !car.scheduled }
      const checkbox = this.element.querySelector(`input[data-car="${car.key}"][type="checkbox"]`)
      if (checkbox) checkbox.checked = car.scheduled
      const label = this.element.querySelector(`[data-car-label="${car.key}"]`)
      if (label) label.textContent = car.plate || (this.state.routing_import ? "Sem placa definida" : car.label)
      const plateSelect = this.element.querySelector(`select[data-car="${car.key}"][data-action*="#plate"]`)
      if (plateSelect) {
        plateSelect.replaceChildren(new Option("Selecionar placa", ""))
        const options = [...this.plateOptionsValue, ...(this.state.routing_import?.rows || []).map(row => row.plate), car.plate].filter(Boolean)
        ;[...new Set(options)].sort().forEach(plate => plateSelect.add(new Option(plate, plate)))
        plateSelect.value = car.plate || ""
        plateSelect.disabled = !car.scheduled
      }
      const routing = this.element.querySelector(`[data-car-routing="${car.key}"]`)
      if (routing) {
        const source = this.state.routing_import?.rows.find(row => row.plate === car.plate)
        routing.textContent = !car.scheduled ? "Sem saída no dia. Não gera falta de colaboradores." : source ? `Mapa(s): ${source.maps.join(", ")} · Motorista no CSV: ${source.driver_code || "não informado"}` : this.state.routing_import ? "Não consta no CSV; confira a saída e a placa desta operação." : ""
        routing.classList.toggle("time-off-shortage", Boolean(this.state.routing_import && car.scheduled && !source))
      }
      const card = this.element.querySelector(`.time-off-car[data-car-key="${car.key}"]`)
      if (card) card.classList.toggle("is-not-scheduled", !car.scheduled)
      const row = this.element.querySelector(`.time-off-route-row[data-car-key="${car.key}"]`)
      if (row) {
        const members = [car.driver, car.helper1, car.helper2].map(id => this.member(id)).filter(Boolean)
        row.hidden = !car.scheduled || (members.length > 0 && !members.some(member => this.matchesFilter(member)))
      }
    })
    const scheduled = this.state.cars.filter(car => car.scheduled)
    const drivers = scheduled.filter(car => car.driver).length
    const driverGap = scheduled.length - drivers
    const helperGap = scheduled.reduce((sum, car) => sum + Number(car.helper_count >= 1 && !car.helper1) + Number(car.helper_count >= 2 && !car.helper2), 0)
    this.driverCountTarget.textContent = `${drivers} / ${scheduled.length}`
    this.carCountTargets.forEach(target => { target.textContent = String(scheduled.length) })
    if (this.hasRoutingReportTarget) {
      const source = this.state.routing_import
      this.routingReportTarget.textContent = source ? `${source.filename}: ${source.rows.length} placas próprias · ${source.ignored_freight} freteiros ignorados. ${scheduled.filter(car => car.operation === "route").length} / ${this.state.cars.filter(car => car.operation === "route").length} rotas padrão sairão. As operações que não constam no CSV precisam de conferência.` : "Importe as placas e mapas do dia. O dimensionamento permanece como capacidade prevista."
    }
    this.helperGapTarget.textContent = String(helperGap)
    this.helperGapTarget.closest("[data-shortage-card]")?.classList.toggle("is-missing", helperGap > 0)
    if (this.hasDriverGapTarget) {
      this.driverGapTarget.textContent = String(driverGap)
      this.driverGapTarget.closest("[data-shortage-card]").classList.toggle("is-missing", driverGap > 0)
    }
    if (this.hasShortageSummaryTarget) this.shortageSummaryTarget.classList.toggle("has-shortage", driverGap > 0 || helperGap > 0)
    const driverLabel = this.element.querySelector('[data-shortage-label="driver"]')
    const helperLabel = this.element.querySelector('[data-shortage-label="helper"]')
    if (driverLabel) driverLabel.textContent = driverGap === 1 ? "motorista faltando" : "motoristas faltando"
    if (helperLabel) helperLabel.textContent = helperGap === 1 ? "ajudante faltando" : "ajudantes faltando"
    this.dirtyTarget.textContent = this.changed ? "Alterações ainda não salvas" : this.revisionValue < 0 ? "Sugestão inicial. Salve para confirmar a composição." : "Composição salva; nenhuma alteração pendente."
  }

  announce(message, error = false) {
    this.messageTarget.textContent = message
    this.messageTarget.classList.toggle("time-off-shortage", error)
    if (this.hasErrorTarget) this.errorTarget.textContent = error ? message : ""
  }

  openSave() {
    if (this.saving || this.importing || !this.editableValue) return
    this.errorTarget.textContent = ""
    this.dialogTarget.showModal()
    this.reasonTarget.focus()
  }

  cancelSave(event) {
    event?.preventDefault()
    if (!this.saving) this.dialogTarget.close()
  }

  async save() {
    if (!this.editableValue || this.saving || this.importing) return
    const reason = this.reasonTarget.value.trim()
    if (reason.length < 4 || reason.length > 500) { this.announce("Informe um motivo entre 4 e 500 caracteres.", true); this.reasonTarget.focus(); return }
    this.saving = true
    this.saveTarget.disabled = true
    this.abortController = new AbortController()
    try {
      const statuses = this.state.members.filter(member => member.status !== this.original.members.find(original => original.id === member.id).status)
        .map(member => ({ member_id: member.id, status: member.status, expected_revision: member.revision }))
      const response = await fetch(this.urlValue, {
        method: "PATCH", credentials: "same-origin", signal: this.abortController.signal,
        headers: { "Accept": "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body: JSON.stringify({ board: { date: this.dateValue, reason, expected_revision: this.revisionValue,
          dimensioning_signature: this.signatureValue, routing_token: this.state.routing_token, cars: this.state.cars.map(car => Object.fromEntries(
            ["operation", "position", "helper_count", "driver", "helper1", "helper2", "plate", "scheduled"].map(key => [key, car[key]])
          )), statuses } })
      })
      if (response.redirected) throw new Error("Sua sessão expirou. Atualize a página para entrar novamente.")
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Não foi possível salvar o painel.")
      this.changed = false
      this.dialogTarget.close()
      Turbo.visit(window.location.href, { action: "replace" })
    } catch (error) {
      if (error.name !== "AbortError") this.announce(error.message === "Failed to fetch" ? "Falha de conexão. Seu rascunho foi mantido; tente salvar novamente." : error.message, true)
    } finally {
      this.saving = false
      if (this.hasSaveTarget) this.saveTarget.disabled = false
    }
  }
}
