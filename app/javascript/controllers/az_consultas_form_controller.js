// az_consultas_form_controller.js
import { Controller } from "@hotwired/stimulus"

// Conecta com data-controller="az-consultas-form"
export default class extends Controller {
  static targets = ["formulario", "titulo", "turnoInput"]

  mostrarFormulario(event) {
    const turno = event.target.dataset.turno;
    const turnoLabel = this.getTurnoLabel(turno);

    // Se o formulário já estiver visível e for o mesmo botão, fecha o formulário
    if (this.formularioTarget.classList.contains("ativo") && this.turnoInputTarget.value === turno) {
      this.fecharFormulario();
    } else {
      // Caso contrário, atualiza o formulário com o novo turno
      this.mudarFormulario(turno, turnoLabel);
    }
  }

  fecharFormulario() {
    // Fecha o formulário com uma transição suave
    this.formularioTarget.classList.remove("ativo");

    // Espera a animação terminar (400ms) antes de aplicar d-none
    setTimeout(() => {
      this.formularioTarget.classList.add("d-none");
    }, 400);
  }

  mudarFormulario(turno, turnoLabel) {
    // Atualiza o título e o valor do turno
    this.tituloTarget.innerText = `Consultar Turno ${turnoLabel}`;
    this.turnoInputTarget.value = turno; // Atualiza o campo oculto

    // Exibe o formulário com transição suave
    this.formularioTarget.classList.remove("d-none");

    requestAnimationFrame(() => {
      this.formularioTarget.classList.add("ativo");
      this.formularioTarget.scrollIntoView({ behavior: "smooth" });
    });
  }

  getTurnoLabel(turno) {
    // Mapeia os valores numéricos para labels amigáveis
    const turnos = {
      "0": "A",
      "1": "B",
      "2": "C"
    };
    return turnos[turno] || turno;
  }
}
