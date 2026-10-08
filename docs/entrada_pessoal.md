# Entrada pessoal

Cada usuário tem uma única Entrada para suas tarefas sem plano de ação. A mesma lista aparece em todos os planos acessíveis e também em **Meu Painel → Minha Entrada**. Criar uma tarefa ali define o usuário conectado como criador e não a vincula ao plano aberto.

Arraste uma tarefa para um bucket do plano ou escolha o destino no campo **Bucket** dos detalhes. A tarefa mantém seu ID, comentários, checklist, datas, recorrência e responsáveis. Ao entrar no plano, ela passa a seguir sua visibilidade e os responsáveis recebem a notificação de atribuição. Só o criador pode devolver uma tarefa comum à própria Entrada. Ações de GEROT permanecem no plano de origem.

A Entrada é privada, inclusive para administradores e usuários selecionados como responsáveis. Enquanto a tarefa estiver ali, seus avisos de vencimento vão apenas ao criador. Etiquetas pertencem aos planos e ficam disponíveis depois do lançamento. Ao devolver uma tarefa à Entrada, suas etiquetas do plano são removidas.

As tarefas da Entrada não entram nos totais, dashboards, calendário do plano, exportação Excel, atribuição em massa ou categorias dos modelos de GEROT. Excluir um plano não exclui a Entrada pessoal.

## Migração dos dados anteriores

Execute `bundle exec rails db:migrate` antes de iniciar a aplicação atualizada. A migração consolida as tarefas das Entradas antigas por criador, preservando os IDs, comentários, checklists, responsáveis e datas. As etiquetas anteriores são registradas no histórico da movimentação antes de seus vínculos ao plano serem removidos. Os avisos dessas tarefas são ajustados para a Entrada do criador.

Uma Entrada antiga que tenha indicadores, vínculos com indicadores de GEROT ou ações geradas passa a ser um bucket comum do mesmo plano, mantendo seus dados e vínculos. Entradas sem esses vínculos são removidas após a consolidação. A migração não pode ser revertida automaticamente, pois reúne tarefas antes distribuídas por vários planos.

## Validação

```sh
PARALLEL_WORKERS=1 bundle exec rails test test/controllers/personal_inbox_test.rb test/models/personal_inbox_test.rb test/migrations/make_inbox_personal_test.rb
```

Para verificar captura, sincronização entre planos, modal, checklist, comentários, movimentação e a Entrada no celular:

```sh
RAILS_ENV=test bundle exec rails assets:precompile
RAILS_ENV=test bundle exec rails runner test/browser/personal_inbox_setup.rb
RAILS_ENV=test bundle exec rails server -b 127.0.0.1 -p 4320
# Em outro terminal:
BASE_URL=http://127.0.0.1:4320 node test/browser/personal_inbox_test.cjs
```
