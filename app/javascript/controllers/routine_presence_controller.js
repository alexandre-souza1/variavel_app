import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {

  static values = {
    routineId: Number,
    currentUserId: Number
  }

  connect() {
    // Usuários que EU estou editando nesta aba.
    this.activeRoutineValueId = null
    this.heartbeatTimer = null

    // Presença recebida dos OUTROS usuários.
    //
    // Estrutura:
    // Map<
    //   routineValueId,
    //   Map<userId, { name, timeout }>
    // >
    this.presence = new Map()

    this.subscription = consumer.subscriptions.create(
      {
        channel: "RoutineChannel",
        routine_id: this.routineIdValue,
        user_id: this.currentUserIdValue
      },
      {
        received: (data) => this.received(data)
      }
    )

    this.handleEditingStart = (event) => {
      this.startEditing(event.detail.routineValueId)
    }

    this.handleEditingStop = (event) => {
      this.stopEditing(event.detail.routineValueId)
    }

    document.addEventListener(
      "routine:editing-start",
      this.handleEditingStart
    )

    document.addEventListener(
      "routine:editing-stop",
      this.handleEditingStop
    )
  }

  disconnect() {
    this.stopEditingLocally()
    this.stopHeartbeat()

    this.presence.forEach((users) => {
      users.forEach((presence) => {
        clearTimeout(presence.timeout)
      })
    })

    this.presence.clear()

    document.removeEventListener(
      "routine:editing-start",
      this.handleEditingStart
    )

    document.removeEventListener(
      "routine:editing-stop",
      this.handleEditingStop
    )

    this.subscription?.unsubscribe()
  }

  // ============================================================
  // EDIÇÃO DO USUÁRIO ATUAL
  // ============================================================

  startEditing(routineValueId) {

    if (
      this.activeRoutineValueId === routineValueId
    ) {
      return
    }

    // Se estava editando outra célula,
    // encerra a anterior.
    if (this.activeRoutineValueId) {
      this.sendStopEditing(
        this.activeRoutineValueId
      )
    }

    this.activeRoutineValueId = routineValueId

    this.subscription.perform(
      "start_editing",
      {
        routine_value_id: routineValueId
      }
    )

    this.startHeartbeat()
  }

  stopEditing(routineValueId) {

    if (
      this.activeRoutineValueId !== routineValueId
    ) {
      return
    }

    this.sendStopEditing(
      routineValueId
    )

    this.activeRoutineValueId = null

    this.stopHeartbeat()
  }

  stopEditingLocally() {

    if (!this.activeRoutineValueId) {
      return
    }

    this.sendStopEditing(
      this.activeRoutineValueId
    )

    this.activeRoutineValueId = null
  }

  sendStopEditing(routineValueId) {

    this.subscription.perform(
      "stop_editing",
      {
        routine_value_id: routineValueId
      }
    )
  }

  startHeartbeat() {

    this.stopHeartbeat()

    this.heartbeatTimer = setInterval(() => {

      if (!this.activeRoutineValueId) {
        return
      }

      this.subscription.perform(
        "editing_heartbeat",
        {
          routine_value_id:
            this.activeRoutineValueId
        }
      )

    }, 3000)
  }

  stopHeartbeat() {

    if (!this.heartbeatTimer) {
      return
    }

    clearInterval(
      this.heartbeatTimer
    )

    this.heartbeatTimer = null
  }

  // ============================================================
  // PRESENÇA DOS OUTROS USUÁRIOS
  // ============================================================

  received(data) {

    // Não mostrar a própria presença.
    if (
      Number(data.user_id) ===
      this.currentUserIdValue
    ) {
      return
    }

    switch (data.type) {

      case "editing_started":
      case "editing_heartbeat":
        this.registerPresence(data)
        break

      case "editing_stopped":
        this.removePresence(
          data.routine_value_id,
          data.user_id
        )
        break

    }
  }

  registerPresence(data) {

    const routineValueId =
      Number(data.routine_value_id)

    const userId =
      Number(data.user_id)

    if (!this.presence.has(routineValueId)) {
      this.presence.set(
        routineValueId,
        new Map()
      )
    }

    const users =
      this.presence.get(routineValueId)

    // Se o usuário já estava presente,
    // apenas reinicia o timeout.
    const existing =
      users.get(userId)

    if (existing) {
      clearTimeout(existing.timeout)
    }

    const timeout = setTimeout(() => {

      this.removePresence(
        routineValueId,
        userId
      )

    }, 7000)

    users.set(
      userId,
      {
        name: data.user_name,
        timeout: timeout
      }
    )

    this.renderPresence(
      routineValueId
    )
  }

  removePresence(
    routineValueId,
    userId
  ) {

    const users =
      this.presence.get(routineValueId)

    if (!users) {
      return
    }

    const user =
      users.get(Number(userId))

    if (user) {
      clearTimeout(user.timeout)
    }

    users.delete(
      Number(userId)
    )

    if (users.size === 0) {
      this.presence.delete(
        routineValueId
      )
    }

    this.renderPresence(
      routineValueId
    )
  }

  renderPresence(routineValueId) {

    const cell = document.querySelector(
      `[data-routine-cell-id-value="${routineValueId}"]`
    )

    if (!cell) {
      return
    }

    const badge = cell.querySelector(
      "[data-routine-presence-badge]"
    )

    if (!badge) {
      return
    }

    const users =
      this.presence.get(routineValueId)

    if (!users || users.size === 0) {

      badge.innerHTML = ""
      badge.classList.add("d-none")
      badge.removeAttribute("title")

      return
    }

  const names =
    Array.from(users.values())
      .map(user => user.name.split(" ")[0])

    badge.innerHTML =
      `<span class="routine-cell__presence-dot"></span>`

    badge.classList.remove("d-none")

    badge.title =
      names.length === 1
        ? `${names[0]} está editando esta célula`
        : `${names.length} pessoas estão editando esta célula:\n${names.join("\n")}`
  }

}
