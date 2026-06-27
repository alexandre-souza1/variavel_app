import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static values = {
    taskId: Number
  }


  connect() {

    if (!this.taskIdValue) return


    setTimeout(() => {

      const task = document.querySelector(
        `[data-task-id="${this.taskIdValue}"]`
      )


      if(task){

        task.click()

      }

    }, 500)

  }

}
