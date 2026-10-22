# Módulo Faltas de checklist

O módulo **Faltas de checklist** fica dentro dos menus **DU, AZ, FROTA e RH**, no desktop e no celular. DU e AZ já abrem com sua área selecionada; Frota e RH podem filtrar as duas áreas. Usa o cadastro único de pessoas e preserva o vínculo das ocorrências com suas ações de origem. Os atalhos nos planos continuam disponíveis. Ele não consulta nem altera o módulo de checklists do aplicativo.

## Registrar e conferir

1. Escolha o ano, a **Área do colaborador** (DU, AZ ou ambas) e, se necessário, um plano de origem. O filtro segue o setor atual ou último setor do cadastro, como no diretório de colaboradores. Ele atualiza os cartões anuais, a tabela, o histórico, o calendário e a identificação em lote. Ações cujo colaborador ainda não foi identificado permanecem para conferência.
2. Ações geradas pelo GEROT como **Investigar % Aderência Paleteira/Empilhadeira/Saída Rota/Retorno Rota fora da meta — NOME** também são identificadas. O vínculo com o indicador determina o tipo, o comentário de origem identifica a pessoa e a data de referência da célula determina a falta quando o comentário não traz uma data explícita. Nomes abreviados só entram no lote quando há correspondência única no cadastro. Indicadores de disponibilidade, produtividade ou tempo de preenchimento não são tratados como falta apenas por estarem fora da meta.
3. Em **Ações para conferir**, use **Registrar N identificadas** para vincular de uma vez os casos com nome e sobrenome únicos, uma data explícita (ou data de referência do GEROT) e um tipo de checklist claro. Não é preciso confirmar cada caso separadamente. O título ou comentário que relata a falta tem prioridade sobre discussões posteriores.
4. Os casos restantes mostram o motivo da conferência. A busca considera acentos, espaços, nomes anteriores do cadastro e sobrenomes abreviados. Primeiros nomes isolados e pequenas diferenças de grafia podem preencher uma sugestão, mas não são registrados automaticamente. Para esses casos, confira os campos e use **Registrar ocorrência**. Os responsáveis pela execução da tarefa não são usados para identificar quem deixou de fazer o checklist.
5. Para outra pessoa, data ou tipo na mesma tarefa, abra a ação e use **Faltas de checklist → Adicionar ocorrência**. Esse campo também está disponível nas tarefas comuns do plano, mesmo quando elas não aparecem nas sugestões.

As próximas ações geradas pelo GEROT aparecem na fila pelos indicadores de aderência acima ou quando o indicador ou o texto da ação menciona checklist. A fila distingue casos prontos para registro em lote e sugestões que ainda precisam de conferência. Só registros efetivados entram na contagem. A identificação em lote preserva ocorrências manuais e registros desconsiderados; não os recria nem os altera. Uma ação sem nome suficiente, um SPOT sem cadastro ou uma investigação sem falta confirmada pode permanecer sem vínculo. Tarefas recorrentes de envio de farol não são classificadas pelo texto genérico da descrição.

## Calendário e consulta das ocorrências

Use as abas **Anual**, **Calendário mensal**, **Histórico** e **Ações para conferir**. Cada aba exibe somente seu conteúdo, sem empilhar as listas abaixo da tabela. O calendário respeita a área e o colaborador selecionados, mostra o total de faltas por dia e permite navegar entre meses e anos. No celular, o dia e o total ficam em destaque; os nomes e tipos aparecem no modal.

Clique no total anual, no total de um mês ou em um dia do calendário para abrir o modal de ocorrências. O modal também exibe as etiquetas de cada tarefa, com suas cores e conforme a permissão de acesso à ação. Os filtros e a posição da página são preservados. A aba **Histórico** também oferece **Ver ocorrências** e, quando houver registros fora da contagem, **Desconsideradas**. Cabeçalho, painéis, abas, tabela, botões e modal usam os componentes compartilhados do aplicativo. A tabela anual segue a tabela de Colaboradores: painel com cabeçalho, avatar com iniciais, nome, matrícula e divisórias entre as linhas. O nome também abre o modal de ocorrências. Fundos e rolagem acompanham o tema selecionado.

## Faltas justificadas que não entram na contagem

No modal, expanda **Não contar esta ocorrência** e escolha **Erro na execução**, **Mapa virado**, **Erro de rede** ou **Outro motivo**. A justificativa é obrigatória para **Outro motivo** e opcional nos motivos padronizados.

Ao salvar, os cartões, a tabela, o histórico e o calendário são atualizados. O registro, autor, data e motivo da decisão continuam disponíveis no modal e na atividade das ações. Todas as ações da mesma combinação de colaborador, data e tipo recebem a justificativa, inclusive em planos diferentes, pois representam a mesma falta. Uma nova ação vinculada posteriormente ao mesmo caso herda a justificativa e não volta a contar. O status da tarefa continua seguindo seu fluxo normal.

O módulo permite justificar ocorrências dos colaboradores que o usuário pode acompanhar, mesmo quando os detalhes da tarefa de origem são privados. O acesso aos detalhes da tarefa continua respeitando suas próprias permissões.

## Regra de contagem

Cada combinação de **colaborador + data + tipo de checklist** representa uma falta. Várias ações sobre a mesma combinação contam uma vez e aparecem juntas no histórico. Saída e retorno no mesmo dia contam duas faltas. Os tipos disponíveis são saída, retorno, empilhadeira, paleteira, segurança e outro.

O ano é determinado pela data da falta, independentemente da criação, vencimento ou conclusão da tarefa. Concluir/reabrir a ação, encerrar o GEROT ou corrigir seu percentual não apaga a falta. O cartão **Com ações abertas** conta faltas que ainda têm pelo menos uma ação aberta, enquanto os demais cartões e a tabela mantêm o total anual. Os filtros de colaborador e mês detalham o histórico; a tabela e os cartões mostram o ano completo do plano selecionado ou dos planos acessíveis.

Para corrigir um lançamento, abra a tarefa e use **Desconsiderar registro**, informando o motivo. O registro original, autor e motivo permanecem na tarefa e na atividade. Depois, registre os dados corretos. Uma tarefa com histórico de ocorrências permanece em seu plano e não pode voltar à Entrada pessoal. Não é permitido excluir tarefas ou colaboradores que sustentem esse histórico.

## Acesso e implantação

O módulo está disponível para os perfis que acompanham colaboradores e para Frota. O acesso da Frota ao módulo não amplia suas permissões para editar o cadastro de RH. DU consulta seus colaboradores; AZ consulta os seus; RH e administradores têm a visão permitida de ambas as áreas. As ocorrências desses colaboradores aparecem no módulo mesmo quando sua ação pertence a um plano privado de outra área. Nesse caso, só a ocorrência e a referência numérica da ação são mostradas: título, nome do plano, GEROT e link para os detalhes continuam protegidos pelas permissões de tarefas.

A fila de identificação, registro em lote e alterações em tarefas continuam exigindo acesso à ação de origem; justificar a contagem de uma ocorrência usa a permissão do próprio módulo e o escopo de colaboradores. Mecânicos e visitantes não têm acesso ao módulo. CPF e outros dados pessoais do cadastro não são exibidos.

Antes de executar a versão atualizada, rode `bundle exec rails db:migrate`. As migrações criam a tabela independente de ocorrências e adicionam a categoria das justificativas. Não transformam sugestões históricas em faltas confirmadas.

Validação:

```sh
PARALLEL_WORKERS=1 bundle exec rails test test/services/checklist_tracking test/controllers/checklist_occurrences_controller_test.rb test/controllers/tasks_controller_test.rb test/controllers/plan_gerots_test.rb test/models/task_test.rb
bundle exec rails assets:precompile
```
