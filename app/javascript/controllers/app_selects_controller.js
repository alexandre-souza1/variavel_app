import { Controller } from "@hotwired/stimulus"

// Aplica o menu das tarefas aos selects comuns, inclusive aos inseridos por
// Turbo ou pelos formulários dinâmicos. O select continua sendo o campo do
// formulário e conserva suas opções, grupos, metadados e eventos.
export default class extends Controller {
  connect() {
    if (!window.TomSelect) return
    this.controls = new Map()
    this.Select = class extends window.TomSelect {
      updateOriginalInput({ silent = false } = {}) {
        if (this.appSyncing) return
        const selected = new Set(this.items)
        for (const option of this.input.options) option.selected = selected.has(option.value)
        if (!this.items.length) this.input.selectedIndex = -1
        if (this.isSetup && !silent) this.trigger("change", this.getValue())
      }
    }
    this.scan(this.element)
    this.observer = new MutationObserver(records => {
      for (const record of records) {
        for (const node of record.addedNodes) if (node.nodeType === Node.ELEMENT_NODE) this.scan(node)
        if (record.type === "attributes" && record.target.matches("fieldset")) {
          for (const state of this.controls.values()) if (record.target.contains(state.element)) this.sync(state)
        }
      }
      for (const [element, state] of this.controls) {
        if (!element.isConnected) this.destroy(state)
      }
    })
    this.observer.observe(this.element, { childList: true, subtree: true, attributes: true, attributeFilter: ["disabled"] })
    this.beforeCache = () => this.cleanup()
    this.reposition = event => {
      for (const state of this.controls.values()) {
        if (state.select.isOpen && !state.select.dropdown.contains(event.target)) this.position(state)
      }
    }
    this.reset = event => {
      // O reset nativo ocorre depois do evento.
      queueMicrotask(() => {
        for (const state of this.controls.values()) if (state.element.form === event.target) this.sync(state)
      })
    }
    document.addEventListener("turbo:before-cache", this.beforeCache)
    document.addEventListener("scroll", this.reposition, true)
    document.addEventListener("reset", this.reset, true)
    window.addEventListener("resize", this.reposition)
    window.visualViewport?.addEventListener("resize", this.reposition)
    window.visualViewport?.addEventListener("scroll", this.reposition)
  }

  disconnect() { this.cleanup() }

  scan(root) {
    if (root.matches("select")) this.enhance(root)
    root.querySelectorAll("select").forEach(element => this.enhance(element))
  }

  enhance(element) {
    if (this.controls.has(element) || element.tomselect || element.size > 1 ||
        element.matches('[data-app-select="native"]') ||
        (element.dataset.controller || "").split(/\s+/).some(name => ["task-select", "tom-select", "tom-select-users"].includes(name))) return

    const computed = getComputedStyle(element)
    const style = {
      paddingTop: computed.paddingTop, paddingLeft: computed.paddingLeft,
      fontSize: computed.fontSize, lineHeight: computed.lineHeight,
      minHeight: computed.minHeight === "auto" ? "0px" : computed.minHeight
    }
    const label = element.labels?.[0]
    const labelFor = label?.getAttribute("for")
    const select = new this.Select(element, {
      create: false,
      allowEmptyOption: true,
      hideSelected: false,
      maxOptions: null,
      lockOptgroupOrder: true,
      dropdownParent: "body",
      plugins: element.multiple ? ["remove_button"] : [],
      ...(element.options.length <= 12 && !element.multiple ? { controlInput: null } : {}),
      render: {
        option: (data, escape) => `<div class="task-select-option"><span>${escape(data.text)}</span><i class="bi bi-check2" aria-hidden="true"></i></div>`
      }
    })
    const state = { element, select, label, labelFor, descriptors: new Map(), syncing: false, pending: false }
    this.controls.set(element, state)
    select.wrapper.classList.add("app-select")
    if (!element.matches(".form-select, .form-control, .form-control-custom, .position-select")) {
      Object.assign(select.wrapper.style, { fontSize: style.fontSize, lineHeight: style.lineHeight, minHeight: style.minHeight })
    }
    select.wrapper.style.setProperty("--app-select-padding-y", style.paddingTop)
    select.wrapper.style.setProperty("--app-select-padding-x", style.paddingLeft)
    select.wrapper.style.setProperty("--app-select-min-height", style.minHeight)
    select.dropdown.classList.add("app-select-menu")
    select.dropdown.style.fontSize = style.fontSize
    select.dropdown.setAttribute("popover", "manual")
    select.positionDropdown = () => this.position(state)
    select.on("dropdown_open", () => {
      for (const other of this.controls.values()) if (other !== state && other.select.isOpen) other.select.close()
      select.dropdown.showPopover?.()
      this.position(state)
    })
    select.on("dropdown_close", () => select.dropdown.hidePopover?.())
    state.search = event => event.stopPropagation()
    for (const name of ["input", "change"]) select.control_input.addEventListener(name, state.search)
    for (const attribute of ["aria-label", "aria-describedby"]) {
      if (element.hasAttribute(attribute)) select.focus_node.setAttribute(attribute, element.getAttribute(attribute))
    }

    // Alterações programáticas não emitem change. Espelhamos value/selectedIndex
    // no menu sem disparar autosave, submit ou os handlers de negócio.
    for (const property of ["value", "selectedIndex"]) {
      const native = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, property)
      state.descriptors.set(property, Object.getOwnPropertyDescriptor(element, property))
      Object.defineProperty(element, property, {
        configurable: true,
        get: () => native.get.call(element),
        set: value => {
          native.set.call(element, value)
          if (!state.syncing) this.sync(state)
        }
      })
    }
    state.change = () => this.sync(state)
    state.invalid = () => { state.reportInvalid = true; this.validation(state); select.focus() }
    element.addEventListener("change", state.change)
    element.addEventListener("invalid", state.invalid)
    state.observer = new MutationObserver(() => {
      if (state.pending) return
      state.pending = true
      queueMicrotask(() => {
        state.pending = false
        if (this.controls.has(element)) this.sync(state)
      })
    })
    state.observer.observe(element, { attributes: true, childList: true, subtree: true, characterData: true })
    this.sync(state)
  }

  sync(state) {
    if (state.syncing) return
    const { element, select } = state
    const values = Array.from(element.selectedOptions, option => option.value)
    state.syncing = select.appSyncing = true
    try {
      select.clear(true)
      select.clearOptions(() => false)
      select.clearOptionGroups()
      const groups = new Map()
      element.querySelectorAll("optgroup").forEach((group, index) => {
        const value = `group-${index}`
        groups.set(group, value)
        select.addOptionGroup(value, { label: group.label, disabled: group.disabled })
      })
      select.addOptions(Array.from(element.options, (option, index) => ({
        value: option.value,
        text: option.textContent.trim(),
        disabled: option.disabled || option.hidden || option.parentElement.disabled === true,
        optgroup: groups.get(option.parentElement),
        $order: index + 1
      })))
      select.setValue(values, true)
      const disabled = element.matches(":disabled")
      if (select.isDisabled !== disabled) {
        select.isDisabled = disabled
        select.focus_node.tabIndex = disabled ? -1 : select.tabIndex
        select.control_input.disabled = disabled
        select.setLocked()
        if (disabled) select.close()
      }
      select.isRequired = element.required
      select.refreshState()
      select.lastQuery = null
      select.refreshOptions(false)
      this.validation(state)
    } finally {
      state.observer.takeRecords()
      state.syncing = select.appSyncing = false
    }
  }

  validation(state) {
    const { element, select } = state
    const invalid = element.classList.contains("is-invalid") || element.getAttribute("aria-invalid") === "true" ||
      (Boolean(state.reportInvalid) && !element.validity.valid)
    select.wrapper.classList.toggle("is-invalid", invalid)
    select.wrapper.classList.toggle("is-valid", element.classList.contains("is-valid"))
    select.focus_node.setAttribute("aria-invalid", String(invalid))
    select.focus_node.setAttribute("aria-required", String(element.required))
    if (element.validity.valid) state.reportInvalid = false
  }

  position(state) {
    const { select } = state
    if (!select.isOpen) return
    const rect = select.control.getBoundingClientRect()
    const viewport = window.visualViewport
    const left = viewport?.offsetLeft || 0, top = viewport?.offsetTop || 0
    const width = viewport?.width || innerWidth, height = viewport?.height || innerHeight
    const below = Math.max(0, top + height - rect.bottom - 12)
    const above = Math.max(0, rect.top - top - 12)
    const upwards = below < 180 && above > below
    const available = upwards ? above : below
    const menuWidth = Math.min(Math.max(rect.width, 160), width - 16)
    Object.assign(select.dropdown.style, {
      position: "fixed", width: `${menuWidth}px`,
      left: `${Math.max(left + 8, Math.min(rect.left, left + width - menuWidth - 8))}px`,
      top: `${rect.bottom + 6}px`
    })
    select.dropdown_content.style.maxHeight = `${Math.max(0, Math.min(280, available - 14))}px`
    if (upwards) select.dropdown.style.top = `${Math.max(top + 8, rect.top - select.dropdown.offsetHeight - 6)}px`
  }

  destroy(state) {
    const { element, select } = state
    const values = Array.from(element.selectedOptions, option => option.value)
    state.observer.disconnect()
    element.removeEventListener("change", state.change)
    element.removeEventListener("invalid", state.invalid)
    for (const name of ["input", "change"]) select.control_input.removeEventListener(name, state.search)
    select.dropdown.hidePopover?.()
    // Conserva opções carregadas dinamicamente e o valor atual no cache Turbo.
    select.revertSettings.innerHTML = element.innerHTML
    for (const [property, descriptor] of state.descriptors) {
      if (descriptor) Object.defineProperty(element, property, descriptor)
      else delete element[property]
    }
    select.destroy()
    for (const option of element.options) option.selected = values.includes(option.value)
    if (!values.length) element.selectedIndex = -1
    if (state.label) {
      if (state.labelFor === null) state.label.removeAttribute("for")
      else state.label.setAttribute("for", state.labelFor)
    }
    this.controls.delete(element)
  }

  cleanup() {
    this.observer?.disconnect()
    if (!this.controls) return
    for (const state of this.controls.values()) this.destroy(state)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    document.removeEventListener("scroll", this.reposition, true)
    document.removeEventListener("reset", this.reset, true)
    window.removeEventListener("resize", this.reposition)
    window.visualViewport?.removeEventListener("resize", this.reposition)
    window.visualViewport?.removeEventListener("scroll", this.reposition)
  }
}
