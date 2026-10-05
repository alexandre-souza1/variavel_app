# Indicadores de expansão

Use `disclosure_arrow` dentro de todo `<summary>`. O helper gera um ícone decorativo do Bootstrap Icons; o componente compartilhado remove o marcador nativo e gira a seta da direita para baixo quando o `<details>` está aberto.

```erb
<details>
  <summary><%= disclosure_arrow %> Ver detalhes</summary>
  <div>Conteúdo</div>
</details>
```

Para preservar uma posição específica, use `disclosure_arrow(css_class: "minha-classe")`. Acordeões e dropdowns de conteúdo recebem o mesmo indicador automaticamente.

A navbar usa um estilo próprio em `components/_navbar.scss`: chevron para baixo na cor do texto, com rotação de 180 graus ao abrir. Isso inclui os dropdowns, o seletor de setor (`app-nav-chevron`) e as seções do menu mobile. Esses controles não usam `disclosure_arrow`.

Nos controles Stimulus, use um botão com `aria-expanded` e `aria-controls`, e alterne a classe `is-expanded` do ícone junto da visibilidade do conteúdo. O Kanban usa esse padrão em `toggle_done_controller.js`.

A cor vem de `--bs-border-color`, com opacidade de 80%. A transição dura 240 ms, passa pela diagonal e respeita a preferência por movimento reduzido. Os estilos ficam em `components/_disclosures.scss`, importado ao final de `application.scss`.
