# Dashboard de cada plano de ação

O seletor do plano tem a opção **Dashboard**, em `/action_plans/:id?view=dashboard`.
A página apresenta totais e gráficos de status, buckets e responsáveis. Os gráficos
filtram a lista de tarefas; os filtros de status, bucket e responsável podem ser
combinados. A lista tem páginas de 10 tarefas e abre o detalhe existente da tarefa.

O filtro de origem muda os indicadores e a lista: todas as tarefas, tarefas com
origem em um GEROT (`routine_value_id`) ou outras tarefas. Os demais filtros mudam
somente a lista, preservando a visão geral do recorte de origem.

Os status são mutuamente exclusivos:

- Concluídas: `completed = true`, mesmo quando o prazo já passou.
- Atrasadas: tarefas abertas com `due_at` anterior ao instante da consulta.
- Abertas no prazo: demais tarefas abertas, incluindo as que não têm prazo.

O nome do bucket não determina o status da tarefa. Uma tarefa com vários
responsáveis conta uma vez no total e uma vez para cada responsável no gráfico.
Os totais seguem `ActionPlan.visible_to` e `Task.visible_for`, incluindo a restrição
de usuários mecânicos às tarefas atribuídas a eles. Os dados são recalculados a
cada navegação ou atualização da página.

Referência de organização: [visão de gráficos do Microsoft Planner](https://support.microsoft.com/en-us/planner/view-charts-of-your-plan-s-progress).
