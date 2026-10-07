import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../../app/javascript/controllers/before_leave_controller.js", import.meta.url), "utf8")
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
  .replace("export default class", "globalThis.BeforeLeaveController = class")

function setup() {
  const window = new EventTarget()
  const document = new EventTarget()
  const confirmations = []
  window.confirm = (message) => { confirmations.push(message); return false }
  const context = vm.createContext({ window, document })
  vm.runInContext(source, context)
  const controller = new context.BeforeLeaveController()
  controller.element = new EventTarget()
  controller.connect()
  return { controller, window, document, confirmations }
}

function unloadEvent() {
  const event = new Event("beforeunload", { cancelable: true })
  Object.defineProperty(event, "returnValue", { value: "", writable: true })
  return event
}

function visit(document) {
  const event = new Event("turbo:before-visit", { cancelable: true })
  document.dispatchEvent(event)
  return event
}

test("dirty checklist blocks Turbo and browser exits; refusing keeps it dirty", () => {
  const { controller, window, document, confirmations } = setup()
  controller.element.dispatchEvent(new Event("input"))
  assert.equal(visit(document).defaultPrevented, true)
  assert.equal(controller.hasChanges, true)
  assert.equal(confirmations.length, 1)
  const event = unloadEvent()
  window.dispatchEvent(event)
  assert.equal(event.defaultPrevented, true)
})

test("confirmed exit, autosave and explicit cancellation allow leaving without a second prompt", () => {
  for (const action of ["confirm", "saved", "cancel"]) {
    const { controller, window, document, confirmations } = setup()
    controller.element.dispatchEvent(new Event("change"))
    if (action === "confirm") {
      window.confirm = () => true
      assert.equal(visit(document).defaultPrevented, false)
    } else if (action === "saved") {
      controller.markAsSaved()
    } else {
      controller.element.dispatchEvent(new Event("allow-leave"))
    }
    assert.equal(controller.hasChanges, false)
    assert.equal(visit(document).defaultPrevented, false)
    const event = unloadEvent()
    window.dispatchEvent(event)
    assert.equal(event.defaultPrevented, false)
    assert.equal(confirmations.length, 0)
  }
})

test("a blocked submit keeps protection while a valid submit allows the redirect", () => {
  const { controller, document } = setup()
  controller.element.dispatchEvent(new Event("input"))
  const prevented = new Event("submit", { cancelable: true })
  prevented.preventDefault()
  controller.element.dispatchEvent(prevented)
  assert.equal(visit(document).defaultPrevented, true)
  controller.element.dispatchEvent(new Event("submit"))
  assert.equal(visit(document).defaultPrevented, false)
})

test("disconnect removes navigation and form listeners before reconnecting", () => {
  const { controller, window, document, confirmations } = setup()
  controller.element.dispatchEvent(new Event("input"))
  controller.disconnect()
  assert.equal(visit(document).defaultPrevented, false)
  const event = unloadEvent()
  window.dispatchEvent(event)
  assert.equal(event.defaultPrevented, false)
  controller.connect()
  controller.element.dispatchEvent(new Event("input"))
  visit(document)
  assert.equal(confirmations.length, 1)
})
