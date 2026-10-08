import { Turbo } from "@hotwired/turbo-rails"

export function updateOpenTaskCount(bucketId) {
  const list = document.getElementById(`open-tasks-${bucketId}`)
  const count = document.getElementById(`open-count-${bucketId}`)
  if (list && count) count.textContent = list.querySelectorAll(":scope > .task-card").length
}

Turbo.StreamActions.task_move = function () {
  const destination = this.targetElements[0]
  const incoming = this.templateContent.querySelector(".task-card")
  let card = document.getElementById(this.getAttribute("task-id"))
  const previousBucketId = card?.dataset.bucketId
  const version = this.getAttribute("version")
  // HTTP and websocket can confirm the same move, or an older confirmation
  // can arrive after a newer one. Preserve the most recent placement.
  if (version && card?.dataset.taskMoveVersion >= version) return

  if (!destination) {
    card?.remove()
    updateOpenTaskCount(previousBucketId)
    return
  }
  // The previous stream only revokes cards in views without the destination.
  // A full confirmation from the destination stream carries the new order.
  if (!incoming) return

  if (card && incoming) {
    for (const attribute of incoming.attributes) card.setAttribute(attribute.name, attribute.value)
    card.replaceChildren(...incoming.childNodes)
  } else if (!card) {
    card = incoming
  }

  const cards = [...destination.children].filter(element => element.matches(".task-card"))
  const siblings = cards.filter(element => element !== card)
  // Each view may show a subset (assignees or a GEROT period). Count only the
  // preceding cards present in this view instead of using the unfiltered rank.
  const precedingIds = new Set(JSON.parse(this.getAttribute("preceding-task-ids") || "[]"))
  const position = siblings.filter(element => precedingIds.has(element.id)).length
  if (card.parentElement !== destination || cards.indexOf(card) !== position) {
    destination.insertBefore(card, siblings[position] || null)
  }
  if (incoming) card.dataset.taskMoveVersion = version
  updateOpenTaskCount(previousBucketId)
  updateOpenTaskCount(card.dataset.bucketId)
}
