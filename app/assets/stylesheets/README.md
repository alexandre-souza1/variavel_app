# Mapa dos assets SCSS

Este diretorio contem o CSS da aplicacao Rails. Os arquivos sao organizados
por responsabilidade para facilitar a localizacao de uma classe sem alterar a
ordem de cascata durante a refatoracao. Os comentarios nos partials descrevem
o grupo de seletores atendido por cada secao.

## Manifesto e ordem de carregamento

`application.scss` e o entrypoint compilado para `application.css`. A ordem
atual do manifesto e:

1. `config/colors` - variaveis Sass de cores legadas.
2. `bootstrap` - estilos do Bootstrap.
3. `components/index` - componentes reutilizaveis.
4. `pages/index` - estilos especificos de telas.
5. `custom/index` - componentes e valores compartilhados.
6. `simple_calendar` - estilos fornecidos pela biblioteca de calendario.
7. `custom/dark_theme` - ajustes do tema escuro.
8. `custom/ticker` - ticker/avisos em movimento.
9. `custom/checklists` - fotos de checklists.
10. `custom/kanban_scroll` - barras de rolagem do Kanban.
11. `custom/calendar_overrides` - ajustes finais do Simple Calendar.

O `require_self` permanece no manifesto para que regras escritas diretamente
em `application.scss` mantenham o comportamento esperado. Nao mover imports
para "organizar" os arquivos: a ordem pode resolver conflitos de cascata.

## Indices

- `components/_index.scss`: importa `alert`, `avatar`, `navbar`,
  `notifications`, cards de consultas, `footer`, `comments`, `kanban`,
  `tasks`, disponibilidade de frota, cards customizados, paineis e modais.
- `pages/_index.scss`: importa as paginas de consultas, notas fiscais,
  catalogo, fornecedor, home, rotinas, tarefas, dashboards, frota e
  downloads.
- `custom/_index.scss`: importa `components`, `variables`, `tokens` e
  `breakpoints`. Os arquivos customizados que dependem de ordem propria sao
  importados diretamente pelo manifesto.

## Componentes

### Componentes simples

- `_alert.scss`: `#flash-container` e os alerts de feedback global.
- `_avatar.scss`: `.avatar*`, `.avatar-circle*`, `.user-avatar-option` e
  `.avatar-group`; controla tamanhos, formatos, selecao e sobreposicao.
- `_comments.scss`: `.comments-box` e os subelementos de comentario
  (`.comment-item`, `.comment-avatar`, `.comment-body`, `.comment-header`,
  `.comment-time`, `.comment-content`).
- `_footer.scss`: `body` e `footer`, mantendo o rodape no fim da pagina.
- `_notifications.scss`: `.notification-toggle`, badge, menu, lista,
  estados de leitura, botoes de limpar/excluir e layout mobile.
- `_tasks.scss`: destaque de tarefas, labels, campos Tom Select e estados de
  tarefas concluidas.

### Componentes de interface

- `_navbar.scss`: `.app-navbar`, marca, seletor de setor, navegacao,
  dropdowns, avatar e controles responsivos do navbar.
- `_app_panels.scss`: `.app-panel`, headers/bodies, tabelas (`.app-table*`),
  secoes de tabela e estruturas de pagina reutilizaveis.
- `_app_modals.scss`: `.app-modal`, cabecalho, corpo, rodape, formularios,
  Tom Select e modal de detalhe de tarefa.
- `_consultas_cards.scss`: cards e carrossel da area de consultas.
- `_consultas_cards_index.scss`: cards da tela de indice de consultas.
- `_kanban.scss`: entrypoint do Kanban; importa os partials abaixo.
- `kanban/_base.scss`: cards de tarefa e action plan, labels, metadados,
  rodape e estados visuais basicos.
- `kanban/_rest.scss`: controles de lembrete, modais de tarefa/action plan,
  filtros, colunas, drag-and-drop e demais regras complementares do Kanban.

### Disponibilidade da frota

- `_fleet_availability.scss`: entrypoint do componente.
- `fleet_availability/_base.scss`: cabecalho, status aberto/bloqueado,
  metricas, placas, tabela, transferencia, feedback e responsividade da
  disponibilidade.

### Cards e templates customizados

- `_custom_cards.scss`: entrypoint do modulo.
- `custom_cards/_base.scss`: cabecalhos, botoes, busca, grids e cards de
  templates.
- `custom_cards/_category.scss`: categorias, indicadores, badges, tags,
  formularios e estados de categoria.

## Paginas

Os arquivos diretamente em `pages/` definem o escopo principal da tela. Os
arquivos com o mesmo nome de uma pasta sao entrypoints que importam uma base e,
quando necessario, uma camada responsiva.

- `_home.scss`: `.workstation-home`, hero, cards de acesso e ajuda.
- `_consultas.scss`: formulario, mapa, lista, tabela e paginacao de consultas.
- `_consultas_show.scss`: relatorio de motorista, periodo, totais,
  parametros, tabelas e alertas.
- `_az_consultas_new.scss`: selecao de turno e formulario de novas consultas.
- `_az_consultas_show.scss`: relatorios AZ, filtros de periodo, tabelas,
  metricas, exportacao e estados de carregamento.
- `_admin_catalog.scss`: `.admin-catalog-page` e `.catalog-form-page`,
  incluindo resumo, tabela, formulario e modal do catalogo.
- `_supplier_show.scss`: resumo, perfil, centros de custo, notas fiscais,
  historico, auditoria e estados vazios do fornecedor.
- `_invoice_entry.scss`: formulario de lancamento, numeros aninhados,
  anexos, botoes de icone e acoes responsivas.
- `_invoice_index.scss`: cabecalho, resumo, filtros, tabela de notas e
  paginacao.
- `_invoice_show.scss`: status, fornecedor, documentos, observacoes e
  auditoria de uma nota.
- `_downloads.scss`: cabecalho, filtros, lista de downloads, cards de arquivo
  e estados vazios.
- `_routines.scss`: cabecalho e grade de rotinas, celulas editaveis, estados,
  colunas fixas e responsividade.
- `_fleet_availability_email_settings.scss`: configuracao de destinatarios,
  chips de e-mail e preview da assinatura.
- `_mechanic_tasks.scss`: resumo, filtros, cards de tarefas, checklist,
  comentarios e estados de conclusao.

### Dashboards e paginas grandes

- `_dashboards.scss`: entrypoint do dashboard de gestao de frotas.
  - `dashboards/_base.scss`: cabecalho, KPIs, graficos, tabelas, filtros,
    acessos rapidos e paineis da pagina.
  - `dashboards/_responsive.scss`: grids e ajustes para larguras menores.
- `_dashboard_finance.scss`: entrypoint do dashboard financeiro.
  - `dashboard_finance/_base.scss`: KPIs financeiros, filtros, graficos,
    categorias, metas e tabelas de faturas.
  - `dashboard_finance/_responsive.scss`: reorganizacao responsiva dos
    paineis, graficos, metas e tabelas.
- `_tasks_index.scss`: entrypoint do dashboard de tarefas.
  - `tasks_index/_base.scss`: planos, tarefas, KPIs, graficos e controles.
  - `tasks_index/_responsive.scss`: grids, listas, cards e filtros em telas
    menores.

## Customizacoes, tokens e configuracao

- `custom/_components.scss`: componentes visuais compartilhados, como
  cabecalhos, botoes, links de voltar, busca, grids, cards e estados. Usa
  variaveis `--bs-*` para acompanhar os temas.
- `custom/_variables.scss`: cores Sass de componentes e badges, incluindo
  variantes claro/escuro.
- `custom/_tokens.scss`: tokens CSS globais em `:root`, como larguras da
  grade de rotinas, alturas de celula e raios de borda.
- `custom/_breakpoints.scss`: limites Sass alinhados ao Bootstrap:
  `$sm`/`$sm-max` (576px), `$md`/`$md-max` (768px) e
  `$lg`/`$lg-max` (992px).
- `custom/_dark_theme.scss`: overrides de cards, modais, dropdowns,
  formularios, tabelas e outros componentes sob `[data-bs-theme="dark"]`.
- `custom/_ticker.scss`: container, faixa, itens e animacao do ticker.
- `custom/_checklists.scss`: proporcao e recorte de fotos de checklist.
- `custom/_kanban_scroll.scss`: espelhos de scroll superior/inferior do
  Kanban.
- `custom/_calendar_overrides.scss`: tabela, cabecalho, dias, tarefas e
  scrollbar do Simple Calendar.

Em `config/` ficam valores Sass antigos que ainda sao consumidos por partes do
estilo:

- `config/_colors.scss`: `$primary-color`, `$secondary-color`, `$light-bg`,
  `$warning-bg` e `$info-bg`.
- `config/_bootstrap_variables.scss`: ponte de import para `colors`.

## Como localizar uma classe

1. Busque o nome exato em `app/assets/stylesheets`:
   `rg "\\.nome-da-classe|#nome-do-id" app/assets/stylesheets`.
2. Se a classe for de uma tela, comece em `pages/`; se for reutilizada, comece
   em `components/`.
3. Para classes de um modulo com muitos estilos, abra primeiro o entrypoint
   (`_kanban.scss`, `_custom_cards.scss`, `_fleet_availability.scss` ou um
   entrypoint de dashboard) e siga os imports.
4. Confira os seletores ancestrais: varias regras sao aninhadas sob o
   container da pagina e nao funcionam fora dele.
5. Confira tambem as camadas finais do manifesto (`dark_theme`,
   `calendar_overrides` etc.), pois elas podem ajustar a aparencia sem
   redefinir a classe principal.

Ao documentar ou refatorar, prefira comentarios de secao que expliquem a
responsabilidade de um grupo. Evite comentarios linha a linha e nao altere
seletor, propriedade, valor, ordem de regra ou import apenas para melhorar a
organizacao.
