import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    this.timeout = null

    this.element.addEventListener(
      "change",
      () => this.queueSave()
    )

    this.element.addEventListener(
      "input",
      () => this.queueSave()
    )
  }

  queueSave() {
    clearTimeout(this.timeout)

    this.timeout = setTimeout(() => {
      this.save()
    }, 1500)
  }

  async save() {

    const formData = new FormData(this.element)

    const checklistId =
      document.getElementById("autosave_id").value

    if (checklistId) {
      formData.append("id", checklistId)
    }

    try {

      const response = await fetch(
        "/checklists/autosave",
        {
          method: "POST",
          headers: {
            "X-CSRF-Token":
              document.querySelector(
                'meta[name="csrf-token"]'
              ).content
          },
          body: formData
        }
      )

      const data = await response.json()

      if (data.checklist_id) {
        document.getElementById(
          "autosave_id"
        ).value = data.checklist_id
      }

      console.log("autosave ok")

    } catch (error) {

      console.error(
        "erro autosave",
        error
      )

    }
  }
}