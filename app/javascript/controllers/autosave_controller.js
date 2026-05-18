import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    this.timeout = null

    this.element.addEventListener(
      "change",
      (event) => this.queueSave(event)
    )

    this.element.addEventListener(
      "input",
      (event) => this.queueSave(event)
    )
  }

  queueSave(event) {
    if (event.target.type === "file") return

    clearTimeout(this.timeout)

    this.timeout = setTimeout(() => {
      this.save()
    }, 1500)
  }

  async save() {

    const formData = new FormData(this.element)
    const hasSelectedFiles = this.hasSelectedFiles()

    this.removeFinalSubmitOnlyFields(formData)

    const checklistId =
      document.getElementById("autosave_id").value

    if (checklistId) {
      formData.append("id", checklistId)
    }

    try {

      const response = await fetch(
        "/checklists/autosave",
        {
          method: "PATCH",
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

      const beforeLeave =
        this.application.getControllerForElementAndIdentifier(
          this.element,
          "before-leave"
        )

      if (beforeLeave && !hasSelectedFiles) {
        beforeLeave.markAsSaved()
      }

      console.log("autosave ok")

    } catch (error) {

      console.error(
        "erro autosave",
        error
      )

    }
  }

  hasSelectedFiles() {
    return Array.from(
      this.element.querySelectorAll('input[type="file"]')
    ).some((input) => input.files.length > 0)
  }

  removeFinalSubmitOnlyFields(formData) {
    Array.from(formData.keys()).forEach((key) => {
      if (
        key.includes("[checklist_photos_attributes]") ||
        key.includes("[checklist_defects_attributes]")
      ) {
        formData.delete(key)
      }
    })

    this.element.querySelectorAll(
      'input[type="file"]'
    ).forEach((input) => {
      formData.delete(input.name)
    })
  }
}
