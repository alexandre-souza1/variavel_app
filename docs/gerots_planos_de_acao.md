# GEROTs dentro dos planos de ação

O plano reúne as tarefas do ano e vários GEROTs, cada um com seu próprio período. Cada plano tem um único modelo de GEROT, criado dentro do próprio plano e reutilizado em todos os períodos. GEROTs independentes continuam usando modelos independentes, sem precisar de um plano.

## Como usar

1. Abra um plano de ação e escolha a aba **GEROTs**.
2. Use **Criar modelo do plano**. O setor vem do plano e cada bucket do plano se torna uma categoria do modelo. A Entrada pessoal fica fora do modelo.
3. Cadastre os indicadores e suas metas nas categorias. Criar, renomear ou reordenar buckets atualiza as categorias automaticamente.
4. Clique em um mês vazio ou em **Gerar GEROT**. O calendário usa o ano do primeiro GEROT do plano, ou o ano de criação do plano enquanto não houver acompanhamentos. Selecione os indicadores; as datas podem ser alteradas para qualquer período. O modelo já é o do plano e as tarefas vão para o bucket da categoria.
5. Escolha quando gerar tarefas. O padrão é **Comentário em indicador fora da meta**; também é possível escolher **Preenchimento fora da meta**, que dispensa o comentário.
6. Gere o GEROT e preencha os indicadores.

No padrão, preencher um indicador fora da meta apenas registra o desvio. Adicionar um comentário a essa célula cria a tarefa no bucket da categoria, incluindo o comentário, indicador, data, valor, meta e vínculo ao GEROT. O comentário também aparece na conversa da tarefa. A comparação usa a meta vigente na data do preenchimento, respeitando a direção do indicador. Comentários em indicadores dentro da meta, manuais, vazios ou sem meta não geram tarefas.

A mesma célula gera no máximo uma tarefa. Novos comentários de um GEROT aberto são acrescentados à tarefa existente. Edições posteriores do valor ficam registradas na atividade da tarefa, inclusive quando o valor volta à meta, e não concluem a ação automaticamente. Uma nova data pode gerar outra tarefa. A criação usa a notificação flutuante do app com um link para a tarefa.

Use **Ações deste GEROT** para consultar as tarefas daquele período. Na aba anual, o resumo de ações abertas leva às ações de todos os GEROTs do plano, com filtro pelo período de origem. A visão padrão é Kanban no desktop e lista no celular, também nessa consulta. Encerrar ou arquivar um GEROT preserva suas tarefas pendentes e interrompe a geração de novas tarefas.

A regra pode ser alterada em **Configurações do GEROT**. A migração aplica o padrão de comentário aos GEROTs existentes, preservando todas as tarefas anteriores. Alterar a regra não gera tarefas retroativas.

No modelo do plano, a categoria corresponde ao bucket e seu nome e posição acompanham os dele. A edição de categorias é feita pelos buckets. Um bucket com preenchimentos de GEROT não pode ser excluído, para preservar o histórico; buckets sem preenchimentos podem ser removidos junto com sua categoria.

## GEROTs independentes e adaptação

O catálogo **Modelos de GEROT** reúne os modelos independentes. É possível cadastrar categorias, indicadores e metas e gerar acompanhamentos diretamente pelo catálogo. Eles aparecem como **Independente** na visão geral e não geram tarefas em planos.

Para conectar um acompanhamento, abra **Vincular um GEROT existente** na aba **GEROTs** do plano. A página de adaptação mostra as categorias e indicadores de origem e exige escolher um bucket para cada categoria. Também permite criar um bucket com o nome da categoria; várias categorias podem ser agrupadas em um bucket.

Ao confirmar, os indicadores e as metas são copiados para o modelo único do plano. Os preenchimentos mantêm seus IDs, valores, comentários e atividades, e as tarefas existentes mantêm seus vínculos. O modelo independente de origem e os demais GEROTs que o usam permanecem independentes. Um novo período adaptado do mesmo modelo e para os mesmos buckets reutiliza os indicadores já copiados. A adaptação não cria tarefas retroativas.

## Registros anteriores

As migrações preservam os GEROTs sem plano como independentes. Os já vinculados são adaptados ao modelo exclusivo do respectivo plano usando os destinos de categoria configurados anteriormente; destinos ausentes criam ou reutilizam buckets com o nome da categoria. Os modelos independentes de origem são preservados. A adaptação dos dados existentes é irreversível pela migração; desfazê-la exige restaurar um backup.

Administradores e o proprietário do plano podem configurar o modelo, gerar e vincular GEROTs. O proprietário pode adaptar seus próprios acompanhamentos independentes do mesmo setor; administradores podem adaptar qualquer acompanhamento independente do setor. Os acessos ao modelo e aos GEROTs vinculados seguem a visibilidade do plano. Um plano com GEROTs não pode ser excluído diretamente. A exclusão de um GEROT, quando autorizada, preserva as tarefas e a descrição de sua origem.

## Preparação e validação

```sh
bundle exec rails db:migrate
bundle exec rails assets:precompile
PARALLEL_WORKERS=1 bundle exec rails test test/controllers/plan_gerot_models_test.rb test/controllers/plan_gerots_test.rb test/controllers/routine_generators_controller_test.rb test/controllers/action_plans_controller_test.rb test/controllers/routines_controller_test.rb test/services/routines/generator_test.rb test/services/routines/goal_evaluation_test.rb test/services/routines/indicator_updater_test.rb test/services/routines/calculation_service_test.rb test/channels/routine_channel_test.rb
```

As migrações adicionam o plano aos GEROTs e ao seu modelo, o bucket à categoria, a origem dos indicadores adaptados, a referência única do preenchimento na tarefa e a regra de geração por GEROT. Há índices únicos para o modelo por plano, a categoria por bucket e o indicador adaptado por origem e categoria. Duplicatas do mesmo período e modelo no mesmo plano são rejeitadas.
