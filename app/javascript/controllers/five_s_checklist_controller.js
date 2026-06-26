import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static targets = [
    "step",
    "nextButton",
    "submitButton"
  ]


  connect() {

    this.current = 0

    this.showStep()

  }



  next() {

    if (this.current < this.stepTargets.length - 1) {

      this.current++

      this.showStep()

    }

  }



  back() {

    if (this.current > 0) {

      this.current--

      this.showStep()

    }

  }



  showStep() {


    this.stepTargets.forEach((step, index)=>{


      step.classList.toggle(
        "d-none",
        index !== this.current
      )


    })



    const lastStep =
      this.current === this.stepTargets.length - 1



    this.nextButtonTarget.classList.toggle(
      "d-none",
      lastStep
    )


    this.submitButtonTarget.classList.toggle(
      "d-none",
      !lastStep
    )


  }

  restart(event) {

    if (
      confirm(
        "Tem certeza que deseja sair desse checklist? O preenchimento será perdido."
      )
    ) {

      fetch(event.currentTarget.dataset.url, {
        method: "POST",
        headers: {
          "X-CSRF-Token":
            document.querySelector("[name='csrf-token']").content
        }
      })
      .then(() => {
        window.location.href = "/checklists"
      })

    }

  }

  cancel() {

    if (!confirm("Tem certeza que deseja sair desse checklist? O preenchimento será perdido.")) {
      return
    }

    this.element
      .closest("[data-controller*='before-leave']")
      ?.dispatchEvent(
        new CustomEvent("allow-leave", { bubbles: true })
      )

    window.location.href = "/checklists"
  }


}
