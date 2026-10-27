import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../../app/javascript/controllers/tread_inspection_controller.js", import.meta.url), "utf8")
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
  .replace('import * as bootstrap from "bootstrap"', "")
  .replace("export default class", "globalThis.TreadInspectionController = class")

function setup(fetch) {
  const tooltip = {
    contents: [],
    disposed: false,
    setContent(content) { this.contents.push(content[".tooltip-inner"]) },
    dispose() { this.disposed = true }
  }
  const context = vm.createContext({
    fetch, AbortController,
    bootstrap: { Tooltip: function () { return tooltip } }
  })
  vm.runInContext(source, context)
  const controller = new context.TreadInspectionController()
  const attributes = new Map()
  controller.element = { setAttribute: (key, value) => attributes.set(key, value) }
  controller.urlValue = "/fleet_availabilities/1/tread_inspection?plate_id=2"
  controller.connect()
  return { controller, tooltip, attributes }
}

test("loads only on demand and reuses the date for subsequent hovers", async () => {
  const requests = []
  const message = "Última aferição de sulcos do veículo: 19/10/2026 às 22:30."
  const { controller, tooltip, attributes } = setup(async (url, options) => {
    requests.push({ url, options })
    return { ok: true, json: async () => ({ message }) }
  })

  assert.equal(requests.length, 0)
  await controller.load()
  await controller.load()

  assert.equal(requests.length, 1)
  assert.equal(requests[0].url, controller.urlValue)
  assert.equal(requests[0].options.headers.Accept, "application/json")
  assert.equal(tooltip.contents[0], message)
  assert.equal(attributes.get("aria-description"), tooltip.contents[0])
})

test("hover and keyboard focus share the pending request", async () => {
  let resolveResponse
  let count = 0
  const { controller } = setup(() => {
    count += 1
    return new Promise(resolve => { resolveResponse = resolve })
  })
  const pending = controller.load()
  await controller.load()
  assert.equal(count, 1)
  resolveResponse({ ok: true, json: async () => ({ message: "Aferição encontrada." }) })
  await pending
})

test("shows an unavailable message and allows retry after a failed request", async () => {
  let count = 0
  const { controller, tooltip } = setup(async () => {
    count += 1
    if (count === 1) return { ok: false }
    return { ok: true, json: async () => ({ message: "Aferição encontrada." }) }
  })

  await controller.load()
  assert.match(tooltip.contents[0], /Não foi possível consultar/)
  await controller.load()
  assert.equal(count, 2)
  assert.match(tooltip.contents[1], /Aferição encontrada/)
})

test("keeps the no history message returned by the server", async () => {
  const { controller, tooltip } = setup(async () => ({
    ok: true,
    json: async () => ({ message: "Última aferição de sulcos do veículo: não encontrada no Prolog." })
  }))
  await controller.load()
  assert.match(tooltip.contents[0], /não encontrada no Prolog/)
})

test("leaving the page aborts the request and disposes the tooltip", async () => {
  const { controller, tooltip } = setup((_url, options) => new Promise((_resolve, reject) => {
    options.signal.addEventListener("abort", () => reject(Object.assign(new Error("aborted"), { name: "AbortError" })))
  }))

  const pending = controller.load()
  controller.disconnect()
  await pending
  assert.equal(tooltip.disposed, true)
  assert.equal(tooltip.contents.length, 0)
})
