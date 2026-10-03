import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["rooms", "pool", "person", "summary", "message", "dirty", "dialog", "reason", "error", "saveButton", "importForm", "importButton", "importReport"]
  static values = { state: Object, url: String, importUrl: String, date: String, revision: Number, plates: Array, rooms: Object, dimensioned: Number }

  connect() {
    this.original = structuredClone(this.stateValue)
    this.state = structuredClone(this.original)
    this.sortables = []
    this.selected = null
    this.changed = false
    this.busy = false
    this.beforeUnload = event => { if (this.changed) { event.preventDefault(); event.returnValue = "" } }
    this.beforeVisit = event => { if (this.changed && !confirm("Descartar o rascunho do PCD ainda não salvo?")) event.preventDefault() }
    window.addEventListener("beforeunload", this.beforeUnload)
    document.addEventListener("turbo:before-visit", this.beforeVisit)
    this.draw()
  }

  disconnect() {
    this.sortables.forEach(item => item.destroy())
    this.abort?.abort()
    window.removeEventListener("beforeunload", this.beforeUnload)
    document.removeEventListener("turbo:before-visit", this.beforeVisit)
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  node(tag, className, text) {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (text !== undefined) node.textContent = text
    return node
  }
  member(id) { return this.state.members.find(m => m.id === id) }
  car(key) { return this.state.cars.find(c => c.key === key) }
  announce(text, error = false) {
    this.messageTarget.textContent = text
    this.errorTarget.textContent = error ? text : ""
    this.messageTarget.classList.toggle("text-danger", error)
  }
  dirty() { this.changed = JSON.stringify(this.state) !== JSON.stringify(this.original); this.draw() }

  select(event) {
    if (this.busy) return
    event.stopPropagation()
    const id = event.currentTarget.closest(".pcd-person").dataset.personId
    if (this.member(id)?.status !== "working") return
    this.selected = this.selected === id ? null : id
    this.draw()
    this.announce(this.selected ? `${this.member(id).name}: toque na vaga de destino.` : "Seleção cancelada.")
  }
  destination(event) {
    event.stopPropagation()
    const drop = event.currentTarget.closest("[data-pcd-drop]")
    if (this.selected && drop) this.move(this.selected, drop.dataset)
  }
  release(event) {
    event.stopPropagation()
    this.move(event.currentTarget.closest(".pcd-person").dataset.personId, {})
  }
  move(id, destination) {
    if (this.busy) { this.draw(); return }
    const member = this.member(id), car = this.car(destination.car)
    if (!member || member.status !== "working") { this.draw(); this.announce("Ajuste a disponibilidade na Escala do dia antes de alocar.", true); return }
    if (car) {
      const valid = car.scheduled && ["driver", "helper1", "helper2"].includes(destination.role) &&
        (destination.role === "driver" ? (car.operation === "van" ? member.cargo === "van" : ["motorista", "van"].includes(member.cargo)) : Number(destination.role.slice(-1)) <= car.helper_count)
      if (!valid) { this.draw(); this.announce("Escolha uma posição compatível. A Van exige Motorista de van.", true); return }
    }
    this.state.cars.forEach(slot => ["driver", "helper1", "helper2"].forEach(role => { if (slot[role] === id) slot[role] = null }))
    if (car) car[destination.role] = id
    this.selected = null
    this.dirty()
    this.announce("Equipe ajustada no rascunho. Salve o PCD para registrar.")
  }

  change(event) {
    if (this.busy) return
    const field = event.currentTarget, car = this.car(field.dataset.car), key = field.dataset.field
    if (key === "plate" && field.value && car.scheduled && this.state.cars.some(other => other.key !== car.key && other.scheduled && other.plate === field.value)) {
      this.draw(); this.announce("Esta placa já está em outra saída. Libere-a antes de transferir.", true); return
    }
    car[key] = key === "scheduled" ? field.checked : key === "helper_count" ? Number(field.value) : field.value
    if (key === "operation") {
      if (["as", "van"].includes(car.operation)) { car.helper_count = 0; car.helper1 = null; car.helper2 = null }
      if (car.operation === "vespertina") { car.helper_count = 1; car.helper2 = null }
      if (car.operation === "van" && this.member(car.driver)?.cargo !== "van") car.driver = null
    }
    if (key === "scheduled" && !car.scheduled) ["driver", "helper1", "helper2"].forEach(role => { car[role] = null })
    if (key === "helper_count") {
      if (car.helper_count < 2) { car.helper2 = null; car.external_helper2 = "" }
      if (car.helper_count < 1) { car.helper1 = null; car.external_helper1 = "" }
    }
    this.dirty()
    this.announce("Alteração no rascunho. Salve para registrar no histórico.")
  }

  input(car, key, type, label, value) {
    const wrapper = this.node("label", "pcd-field", label)
    const input = this.node("input", "form-control form-control-sm")
    input.type = type; input.value = value || ""; input.dataset.car = car.key; input.dataset.field = key; input.dataset.action = "change->pcd#change"
    input.setAttribute("aria-label", `${label} da saída ${car.key}`)
    input.maxLength = key === "notes" ? 500 : 150
    wrapper.append(input)
    return wrapper
  }
  selectField(car, key, label, options) {
    const wrapper = this.node("label", "pcd-field", label)
    const select = this.node("select", "form-select form-select-sm")
    options.forEach(([text, value]) => select.add(new Option(text, value)))
    select.value = String(car[key] ?? ""); select.dataset.car = car.key; select.dataset.field = key; select.dataset.action = "change->pcd#change"
    select.setAttribute("aria-label", `${label} da saída ${car.key}`)
    wrapper.append(select)
    return wrapper
  }
  person(member, assigned) {
    const template = this.personTargets.find(t => t.dataset.personId === member.id)
    const node = template.content.firstElementChild.cloneNode(true)
    node.querySelector(".pcd-person-remove").hidden = !assigned
    node.querySelector(".pcd-person-select").setAttribute("aria-pressed", String(this.selected === member.id))
    node.classList.toggle("is-selected", this.selected === member.id)
    return node
  }
  drop(car, role, label) {
    const wrapper = this.node("div", "pcd-position")
    wrapper.append(this.node("span", "pcd-position-label", label))
    const drop = this.node("div", "pcd-drop")
    drop.dataset.pcdDrop = ""; drop.dataset.car = car.key; drop.dataset.role = role; drop.dataset.action = "click->pcd#destination"
    const member = this.member(car[role])
    if (member) drop.append(this.person(member, true))
    const button = this.node("button", "pcd-vacancy", car.freight && role === "driver" ? "Alocar motorista cadastrado" : `Falta ${role === "driver" ? "motorista" : "ajudante"}`)
    button.type = "button"; button.dataset.action = "pcd#destination"; drop.append(button)
    drop.classList.toggle("is-filled", Boolean(member))
    wrapper.append(drop)
    this.sortable(drop)
    return wrapper
  }
  sortable(drop) {
    this.sortables.push(Sortable.create(drop, { group: "pcd", draggable: '.pcd-person[data-movable="true"]', sort: false, forceFallback: true, fallbackOnBody: true, fallbackTolerance: 3, emptyInsertThreshold: 15, delay: 150, delayOnTouchOnly: true, animation: 100, filter: '.pcd-person-remove', preventOnFilter: false,
      onEnd: event => event.from === event.to ? this.draw() : this.move(event.item.dataset.personId, event.to.dataset) }))
  }
  route(car) {
    const card = this.node("article", `pcd-route${car.freight ? " is-freight" : ""}${car.scheduled ? "" : " is-cancelled"}`)
    card.dataset.carKey = car.key
    const header = this.node("header")
    header.append(this.node("strong", "", car.plate || `Sem placa · ${car.operation === "route" ? "Rota" : car.operation.toUpperCase()} ${Number(car.position || 0) + 1}`), this.node("span", "pcd-route-type", car.freight ? "Freteiro" : "Próprio"))
    card.append(header)
    const toggle = this.node("label", "pcd-departure", "")
    const checkbox = this.node("input"); checkbox.type = "checkbox"; checkbox.checked = car.scheduled; checkbox.dataset.car = car.key; checkbox.dataset.field = "scheduled"; checkbox.dataset.action = "change->pcd#change"
    toggle.append(checkbox, document.createTextNode(" Saída prevista")); card.append(toggle)
    if (!car.scheduled) { card.append(this.node("p", "time-off-muted", "Sem saída no dia. Não gera falta de equipe.")); return card }
    const info = this.node("div", "pcd-route-fields")
    const plateOptions = [...new Set([...this.platesValue, ...this.state.cars.flatMap(c => [c.plate, c.imported_plate]).filter(Boolean)])].sort()
    info.append(this.selectField(car, "plate", "Placa", [["Selecionar placa", ""], ...plateOptions.map(v => [v, v])]), this.selectField(car, "room", "Sala", Object.entries(this.roomsValue).map(([key, value]) => [value[0], key])), this.input(car, "departure_time", "time", "Saída", car.departure_time))
    info.append(this.selectField(car, "operation", "Operação", [["Rota padrão", "route"], ["Vespertina", "vespertina"], ["AS", "as"], ["Van", "van"]]))
    card.append(info)
    if (car.external_driver_code && !car.freight) card.append(this.node("small", "time-off-muted", `Motorista informado no CSV: ${car.external_driver_code}`))
    if (!car.maps.length) card.append(this.node("p", "pcd-missing-map", "Sem mapa no CSV. Confira esta operação."))
    car.maps.forEach(map => {
      const details = this.node("details", "pcd-map")
      details.append(this.node("summary", "", `Mapa ${map.number} · ${map.cities || "Cidades não informadas"}`), this.node("p", "", map.region || "Região não informada"), this.node("small", "", `${map.deliveries || "—"} entregas · ${map.boxes || "—"} caixas · ${map.km || "—"} km · ${map.duration || "—"}`))
      card.append(details)
    })
    card.append(this.drop(car, "driver", "Motorista"))
    if (car.freight) card.append(this.input(car, "external_driver", "text", `Motorista externo · código ${car.external_driver_code || "não informado"}`, car.external_driver))
    for (let n = 1; n <= car.helper_count; n++) {
      card.append(this.drop(car, `helper${n}`, `Ajudante ${n}`))
      if (car.freight) card.append(this.input(car, `external_helper${n}`, "text", `Ajudante externo ${n}`, car[`external_helper${n}`]))
    }
    card.append(this.selectField(car, "helper_count", "Composição", [["Sem ajudante", 0], ["1 ajudante", 1], ["2 ajudantes", 2]]), this.input(car, "notes", "text", "Observação", car.notes))
    return card
  }
  draw() {
    this.sortables.forEach(item => item.destroy()); this.sortables = []
    this.roomsTarget.replaceChildren()
    Object.entries(this.roomsValue).forEach(([room, [label]]) => {
      const cars = this.state.cars.filter(car => car.room === room)
      if (!cars.length) return
      const group = this.node("section", "pcd-room"); group.dataset.room = room
      group.append(this.node("h3", "", `${label} · ${cars.filter(c => c.scheduled).length} saídas`))
      const grid = this.node("div", "pcd-route-grid"); cars.forEach(car => grid.append(this.route(car))); group.append(grid); this.roomsTarget.append(group)
    })
    const used = new Set(this.state.cars.flatMap(car => [car.driver, car.helper1, car.helper2]).filter(Boolean))
    this.poolTargets.forEach(pool => {
      const status = pool.dataset.status
      pool.replaceChildren()
      const people = this.state.members.filter(m => !used.has(m.id) && (m.status === "working" ? "working" : ["off", "dsr"].includes(m.status) ? "off" : "unavailable") === status)
      people.forEach(m => pool.append(this.person(m, false)))
      this.element.querySelector(`[data-pool-count="${status}"]`).textContent = String(people.length)
      if (status === "working") { pool.dataset.pcdDrop = ""; pool.dataset.action = "click->pcd#destination"; this.sortable(pool) }
      if (!people.length) pool.append(this.node("p", "time-off-muted", "Nenhum colaborador nesta lista."))
    })
    const scheduled = this.state.cars.filter(c => c.scheduled), own = scheduled.filter(c => !c.freight)
    this.summaryTarget.replaceChildren()
    const values = [[scheduled.length, "saídas previstas"], [own.length, "próprias"], [scheduled.length - own.length, "freteiros"], [own.filter(c => !c.driver).length, "motoristas faltando"], [own.reduce((sum, c) => sum + Number(c.helper_count >= 1 && !c.helper1) + Number(c.helper_count >= 2 && !c.helper2), 0), "ajudantes faltando"]]
    values.forEach(([number, label]) => { const item = this.node("div"); item.append(this.node("strong", "", String(number)), this.node("span", "", label)); if (label.includes("faltando") && number) item.classList.add("is-missing"); this.summaryTarget.append(item) })
    this.dirtyTarget.textContent = this.changed ? "Alterações ainda não salvas" : this.revisionValue < 0 ? "Sugestão inicial. Salve para confirmar." : "PCD salvo; nenhuma alteração pendente."
    if (this.source) this.importReportTarget.textContent = `${this.source.filename}: ${this.source.rows.filter(r => !r.freight).length} próprias + ${this.source.rows.filter(r => r.freight).length} freteiros · ${this.source.rows.reduce((n, r) => n + r.maps.length, 0)} mapas. Prévia aguardando salvamento.`
  }

  async importFile(event) {
    event.preventDefault()
    if (this.busy || !this.importFormTarget.reportValidity()) return
    this.busy = true; this.importButtonTarget.disabled = true; this.abort = new AbortController()
    try {
      const response = await fetch(this.importUrlValue, { method: "POST", body: new FormData(this.importFormTarget), signal: this.abort.signal, credentials: "same-origin", headers: this.headers() })
      if (response.redirected) throw new Error("Sua sessão expirou. Entre novamente.")
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Falha na importação.")
      // Preserve edits made in this draft to maps already imported; CSV supplies route data.
      const fields = ["scheduled", "operation", "driver", "helper1", "helper2", "room", "departure_time", "helper_count", "external_driver", "external_helper1", "external_helper2", "notes", "plate"]
      const cars = result.cars.map(car => {
        const previous = this.state.cars.find(c => c.key === car.key)
        const original = this.original.cars.find(c => c.key === car.key)
        if (previous && original) fields.forEach(field => { if (previous[field] !== original[field]) car[field] = previous[field] })
        return car
      })
      this.state.cars = cars; this.source = result.source; this.token = result.token; this.selected = null; this.changed = true; this.draw()
      this.announce("CSV carregado na prévia, incluindo freteiros. Confira as equipes, salas e horários e salve.")
    } catch (error) { if (error.name !== "AbortError") this.announce(error.message, true) }
    finally { this.busy = false; if (this.hasImportButtonTarget) this.importButtonTarget.disabled = false }
  }
  headers() { return { "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" } }
  reset() {
    if (this.busy) return
    this.state = structuredClone(this.original); this.source = null; this.token = null; this.selected = null; this.changed = false; this.draw()
    this.importReportTarget.textContent = "Rascunho desfeito. A importação pendente não foi gravada."
    this.announce("Rascunho desfeito.")
  }
  openSave() { if (!this.busy) { this.errorTarget.textContent = ""; this.dialogTarget.showModal(); this.reasonTarget.focus() } }
  cancel(event) { event?.preventDefault(); if (!this.busy) this.dialogTarget.close() }
  async save() {
    if (this.busy) return
    const reason = this.reasonTarget.value.trim()
    if (reason.length < 4 || reason.length > 500) { this.errorTarget.textContent = "Informe um motivo entre 4 e 500 caracteres."; return }
    this.busy = true; this.saveButtonTarget.disabled = true; this.abort = new AbortController()
    try {
      const fields = ["key", "plate", "scheduled", "operation", "helper_count", "driver", "helper1", "helper2", "room", "departure_time", "external_driver", "external_helper1", "external_helper2", "notes"]
      const response = await fetch(this.urlValue, { method: "PATCH", signal: this.abort.signal, credentials: "same-origin", headers: { ...this.headers(), "Content-Type": "application/json" }, body: JSON.stringify({ board: { reason, expected_revision: this.revisionValue, routing_token: this.token, cars: this.state.cars.map(car => Object.fromEntries(fields.map(key => [key, car[key]]))) } }) })
      if (response.redirected) throw new Error("Sua sessão expirou. Entre novamente.")
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Não foi possível salvar.")
      this.changed = false; this.dialogTarget.close(); Turbo.visit(window.location.href, { action: "replace" })
    } catch (error) { if (error.name !== "AbortError") this.announce(error.message, true) }
    finally { this.busy = false; if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = false }
  }
}
