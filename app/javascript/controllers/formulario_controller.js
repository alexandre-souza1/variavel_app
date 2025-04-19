import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["formulario", "titulo", "categoriaInput"]

  mostrarFormulario(event) {
    const categoria = event.target.dataset.categoria;

    // Se o formulário já estiver visível e for o mesmo botão, fecha o formulário
    if (this.formularioTarget.classList.contains("ativo") && this.categoriaInputTarget.value === categoria) {
      this.fecharFormulario();
    } else {
      // Caso contrário, atualiza o formulário com a nova categoria
      this.mudarFormulario(categoria);
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

  mudarFormulario(categoria) {
    // Atualiza o título e o valor da categoria
    this.tituloTarget.innerText = `Consultar ${categoria.charAt(0).toUpperCase() + categoria.slice(1)}`;
    this.categoriaInputTarget.value = categoria; // Atualiza o campo oculto

    // Exibe o formulário com transição suave
    this.formularioTarget.classList.remove("d-none");

    requestAnimationFrame(() => {
      this.formularioTarget.classList.add("ativo");
      this.formularioTarget.scrollIntoView({ behavior: "smooth" });
    });
  }
}
