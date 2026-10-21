import { Controller } from "@hotwired/stimulus"
import { Offcanvas } from "bootstrap"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  connect() {
    this.markCurrentDestination()
  }

  markCurrentDestination() {
    const current = new URL(window.location.href)
    const links = [...this.element.querySelectorAll(".app-mobile-nav-link")]
    let bestMatch
    let bestScore = -1

    links.forEach(link => {
      link.classList.remove("is-active")
      link.removeAttribute("aria-current")
      const destination = new URL(link.href)
      const exact = current.pathname === destination.pathname || (current.pathname === "/" && destination.pathname === "/variaveis")
      const descendant = destination.pathname !== "/" && current.pathname.startsWith(`${destination.pathname}/`)
      if (!exact && !descendant) return
      if (![...destination.searchParams].every(([key, value]) => current.searchParams.get(key) === value)) return

      const score = destination.pathname.length + (exact ? 1000 : 0) + destination.searchParams.size
      if (score > bestScore) {
        bestMatch = link
        bestScore = score
      }
    })

    if (!bestMatch) return
    bestMatch.classList.add("is-active")
    bestMatch.setAttribute("aria-current", new URL(bestMatch.href).pathname === current.pathname ? "page" : "location")
    const section = bestMatch.closest(".app-mobile-nav-section")
    if (!section) return
    this.element.querySelectorAll(".app-mobile-nav-section").forEach(candidate => {
      const active = candidate === section
      candidate.classList.toggle("is-current", active)
      candidate.querySelector(".collapse").classList.toggle("show", active)
      candidate.querySelector("button").setAttribute("aria-expanded", String(active))
    })
  }

  navigate(event) {
    const link = event.target.closest("a[href]")
    if (!link || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    if (link.target || link.hasAttribute("download") || !this.element.classList.contains("show")) return
    if (new URL(link.href).origin !== window.location.origin) return

    event.preventDefault()
    this.element.addEventListener("hidden.bs.offcanvas", () => Turbo.visit(link.href), { once: true })
    Offcanvas.getOrCreateInstance(this.element).hide()
  }

  resize() {
    if (window.matchMedia("(min-width: 992px)").matches) {
      Offcanvas.getInstance(this.element)?.hide()
    }
  }

  rememberBody() {
    this.bodyOverflow = document.body.style.overflow
    this.bodyPadding = document.body.style.paddingRight
  }

  beforeCache() {
    if (!this.element.matches(".show, .showing, .hiding")) return
    Offcanvas.getInstance(this.element)?.hide()
    this.element.classList.remove("show", "showing", "hiding")
    this.element.removeAttribute("aria-modal")
    this.element.removeAttribute("role")
    document.querySelector(".offcanvas-backdrop")?.remove()
    document.body.style.overflow = this.bodyOverflow || ""
    document.body.style.paddingRight = this.bodyPadding || ""
  }
}
