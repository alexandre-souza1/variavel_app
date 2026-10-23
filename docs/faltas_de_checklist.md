# Módulo Acompanhamento de Checklist

O módulo **Acompanhamento de Checklist** fica dentro dos menus **DU, AZ, FROTA e RH**, no desktop e no celular. DU e AZ já abrem com sua área selecionada; Frota e RH podem filtrar as duas áreas. Usa o cadastro único de pessoas e preserva o vínculo das ocorrências com suas ações de origem. Os atalhos nos planos continuam disponíveis. Ele não consulta nem altera o módulo de checklists do aplicativo.

## Registro automático de novas tarefas

Ao salvar uma tarefa comum ou gerar uma ação pelo GEROT, a identificação é processada automaticamente em segundo plano, após confirmar a gravação. Havendo colaborador ou placa SPOT, data e tipo suficientes, a ocorrência é vinculada e passa a contar sem registro manual nem clique no lote. As mesmas regras de nome, cargo, área, indicador e deduplicação continuam valendo.

Alterações da tarefa, novos comentários que relatem a falta e etiquetas também provocam uma nova tentativa, enquanto a tarefa ainda não tiver registros de ocorrência. O processamento usa o acesso do criador da tarefa e registra a identificação automática no log. Casos sem nome/placa, com datas ou identidades ambíguas e incompatíveis com a função permanecem em **Ações para conferir**. Uma tarefa cujo título traz somente uma data (como **— 19/09**) não identifica por si só quem deixou de fazer o checklist.

Ocorrências já registradas, correções e justificativas não são sobrescritas. Várias tarefas da mesma pessoa/placa, data e tipo continuam representando uma única falta. O botão de identificação em lote permanece disponível para ações antigas e reprocessamento dos casos claros. O modal de tarefas não exibe o formulário de faltas de checklist; a conferência e as justificativas ficam neste módulo.

## Registrar e conferir

1. Escolha o ano e a **Área do colaborador** (DU, AZ ou ambas). Os planos de origem são definidos nas configurações compartilhadas do módulo, sem filtro de plano na tela de acompanhamento. O filtro segue o setor atual ou último setor do cadastro, como no diretório de colaboradores. Ele atualiza os cartões anuais, a tabela, o histórico, o calendário e a identificação em lote. Ações cujo colaborador ainda não foi identificado permanecem para conferência.
2. Ações geradas pelo GEROT como **Investigar % Aderência Paleteira/Empilhadeira/Saída Rota/Retorno Rota fora da meta — NOME** também são identificadas. O vínculo com o indicador determina o tipo, o comentário de origem identifica a pessoa e a data de referência da célula determina a falta quando o comentário não traz uma data explícita. Nomes abreviados só entram no lote quando há correspondência única no cadastro. Indicadores de disponibilidade, produtividade ou tempo de preenchimento não são tratados como falta apenas por estarem fora da meta.
3. Em **Ações para conferir**, use **Registrar N identificadas** para vincular de uma vez os casos com nome e sobrenome únicos, uma data explícita (ou data de referência do GEROT) e um tipo de checklist claro. Não é preciso confirmar cada caso separadamente. O título ou comentário que relata a falta tem prioridade sobre discussões posteriores.
4. Os casos restantes mostram o motivo da conferência. A busca considera acentos, espaços, nomes anteriores do cadastro e sobrenomes abreviados. Primeiros nomes isolados e pequenas diferenças de grafia podem preencher uma sugestão, mas não são registrados automaticamente. Para esses casos, confira os campos e use **Registrar ocorrência**. Os responsáveis pela execução da tarefa não são usados para identificar quem deixou de fazer o checklist.
5. O registro manual fica na aba **Ações para conferir** do módulo. O modal de tarefas mantém os campos próprios da ação, sem o bloco de registro de faltas de checklist.

As ações do GEROT são avaliadas pelos indicadores de aderência acima ou quando o indicador ou o texto menciona checklist. Casos claros são registrados automaticamente; pendências e ações antigas continuam na fila para conferência ou reprocessamento em lote. Só registros efetivados entram na contagem. A identificação em lote preserva ocorrências manuais e registros desconsiderados; não os recria nem os altera. Uma ação sem nome suficiente, uma placa SPOT ausente ou uma investigação sem falta confirmada pode permanecer sem vínculo. Tarefas recorrentes de envio de farol não são classificadas pelo texto genérico da descrição.

## Configurações dos planos de origem

O botão **Configurações** abre um painel lateral no próprio acompanhamento. Os planos são carregados ao abrir; cancelar fecha o painel, e salvar atualiza o acompanhamento preservando a aba e os filtros. Administradores e supervisores do setor **Frota** selecionam quais planos de origem ficam visíveis no módulo. A escolha vale para todos os usuários e afeta os acompanhamentos, o histórico, o modal, a fila de conferência e a identificação automática/em lote. O formulário permite alterar apenas planos aos quais o gestor tem acesso; configurações de planos privados fora desse acesso são preservadas. Supervisores de outros setores e usuários comuns não podem alterar essa configuração.

Desmarcar um plano preserva as tarefas, ocorrências e justificativas existentes. Marcar novamente faz os registros reaparecerem. Novos planos começam visíveis. A configuração não concede acesso aos detalhes privados das tarefas e não é substituída por parâmetros de filtro enviados na URL.

## Calendário e consulta das ocorrências

Use as abas **Anual**, **Calendário mensal**, **Histórico** e **Ações para conferir**. Cada aba exibe somente seu conteúdo, sem empilhar as listas abaixo da tabela. O calendário respeita a área e o colaborador selecionados, mostra o total de faltas por dia e permite navegar entre meses e anos. No celular, o dia e o total ficam em destaque; os nomes e tipos aparecem no modal.

Os acompanhamentos **Anual** e **Calendário mensal** incluem somente colaboradores ativos da área selecionada que realizam checklist, inclusive os que têm **zero ocorrências**. Ajudantes DU ficam fora dessas listas e das opções de registro; ajudantes AZ continuam disponíveis. A identificação considera a função atual ou a última função do cadastro, respeitando as datas de promoções e transferências. A tabela anual mostra zero nos meses sem faltas, e o calendário tem uma lista mensal de colaboradores com seus totais, incluindo zero. Os cartões contam faltas e colaboradores com registros; a presença de uma linha zerada não aumenta esses indicadores. Arquivados e cadastros históricos continuam disponíveis na aba **Histórico** e na conferência de ações antigas. O modal aberto por um dia do calendário usa o mesmo escopo de ativos, para manter o total consistente com o dia selecionado.

Clique no total anual, no total de um mês ou em um dia do calendário para abrir o modal de ocorrências. O modal também exibe as etiquetas de cada tarefa, com suas cores e conforme a permissão de acesso à ação. Os filtros e a posição da página são preservados. A aba **Histórico** também oferece **Ver ocorrências** e, quando houver registros fora da contagem, **Desconsideradas**. Cabeçalho, painéis, abas, tabela, botões e modal usam os componentes compartilhados do aplicativo. A tabela anual segue a tabela de Colaboradores: painel com cabeçalho, avatar com iniciais, nome, matrícula e divisórias entre as linhas. O nome também abre o modal de ocorrências. Fundos e rolagem acompanham o tema selecionado.

## Faltas justificadas que não entram na contagem

No modal, expanda **Não contar esta ocorrência** e escolha **Erro na execução**, **Mapa virado**, **Erro de rede** ou **Outro motivo**. A justificativa é obrigatória para **Outro motivo** e opcional nos motivos padronizados.

Ao salvar, a própria resposta atualiza os cartões, a tabela ou calendário em exibição e o modal, sem buscar a página completa nem fazer requisições adicionais de atualização. O modal abre imediatamente com um indicador de carregamento. A análise de tarefas candidatas fica restrita à aba de conferência; as demais abas e o modal não carregam os históricos de nomes para fazer essa análise. O registro, autor, data e motivo da decisão continuam disponíveis no modal e na atividade das ações. Todas as ações da mesma combinação de colaborador, data e tipo recebem a justificativa, inclusive em planos de origem diferentes que estejam habilitados no módulo, pois representam a mesma falta. Uma nova ação vinculada posteriormente ao mesmo caso herda a justificativa e não volta a contar. O status da tarefa continua seguindo seu fluxo normal.

O módulo permite justificar ocorrências dos colaboradores que o usuário pode acompanhar, mesmo quando os detalhes da tarefa de origem são privados. O acesso aos detalhes da tarefa continua respeitando suas próprias permissões.

## Ex-colaboradores sem cadastro anterior

Em **Ações para conferir**, use **Cadastrar ex-colaborador**, ou **Não encontrou? Cadastrar ex-colaborador** abaixo do registro de uma ação. O cadastro abre em um modal, sem sair da tela. Ao salvar, o ex-colaborador fica disponível na seleção e a identificação em lote é atualizada, preservando os filtros e os dados preenchidos na ação. Erros de validação aparecem no próprio modal. A opção está disponível para quem já pode gerenciar colaboradores no RH, respeitando os setores permitidos.

Informe o nome completo e o setor/cargo exercido na época. Matrícula e datas são opcionais; não são criadas datas de saída, matrículas ou códigos Promax fictícios. O cadastro nasce **histórico e inativo**, aparece entre os **Arquivados** de Colaboradores e na seleção de pessoas do rastreio. Não cria perfis operacionais nem entra na equipe ativa, escalas ou disponibilidade. A criação fica auditada com o usuário e o cargo informado.

Após cadastrar, selecione a pessoa na ação ou use **Registrar N identificadas** para reconhecer de uma vez as outras tarefas com nome e contexto claros. O cadastro sozinho não confirma ocorrências. Os registros continuam agrupados por pessoa, data e tipo; as mesmas regras de cargo valem, inclusive a proibição de contar checklist para ajudante DU.

Se forem informadas datas de início ou fim, ações fora desse período exigem revisão do histórico e não entram na contagem. Datas desconhecidas ficam em branco; nesse caso o cargo informado é usado na conferência das ações antigas. Nomes já cadastrados geram um aviso para conferir os inativos. Homônimos com matrículas diferentes podem ser cadastrados, mantendo as tarefas ambíguas para conferência. Cadastros históricos não podem ser reativados pelo botão comum.

## Placas SPOT

No filtro **Acompanhar**, selecione **Placas SPOT** e clique em **Filtrar**. Essa visão tem seus próprios totais anuais, tabela por placa e mês, calendário, histórico e fila para registro em lote. As faltas dos colaboradores permanecem na visão **Colaboradores**.

A identificação aceita estes formatos:

- **Aplicar matriz ao SPOT IZI3B97 por não realização do Checklist de Saída no dia 29/04/2026**: placa, tipo e data vêm do texto.
- **Investigar % Aderência SPOT fora da meta — DLL4A97**: a placa vem do comentário de origem e a data da referência da célula do GEROT. Conforme a regra da operação, **% Aderência SPOT significa checklist de saída**.

A etiqueta **SPOT** ajuda a classificar a ação e aparece na conferência e no modal. Uma placa válida não precisa estar no cadastro de frota nem ser cadastrada como colaborador. Letras são normalizadas para maiúsculas, sem hífen; tanto placas antigas quanto Mercosul são aceitas. Placas ausentes ou múltiplas, datas ambíguas e tipos conflitantes ficam para conferência.

Cada combinação **placa + data + tipo** conta uma falta, ainda que haja várias tarefas. As ocorrências aparecem no modal ao clicar na placa, no total ou no dia do calendário. A opção **Não contar esta ocorrência** mantém a justificativa e o rastreio. Os registros SPOT, as justificativas e o registro em lote respeitam o acesso às tarefas de origem; ações privadas não ficam visíveis por compartilharem a mesma placa.

## Área e função do colaborador

As etiquetas aparecem também nas ações para conferir, inclusive com a ação recolhida. Etiquetas com DU, AZ ou Armazém ajudam a restringir a área; etiquetas de ambas as áreas exigem conferência. Elas não alteram as permissões de acesso.

A identificação usa a função vigente **na data da ocorrência**:

- Ajudante AZ: checklist de paleteira.
- Operador AZ: checklist de empilhadeira.
- Motorista DU: checklist de saída ou retorno. O cargo sozinho não distingue os dois.
- Ajudante DU: não realiza checklist e não entra na contagem de faltas.

Um primeiro nome só pode entrar no lote se houver uma única pessoa compatível com o nome e o contexto de área, cargo ou tipo. Homônimos compatíveis, informações conflitantes e grafia apenas semelhante continuam para conferência. Sem histórico de cargo, o sistema não usa uma função presumida para desempatar nomes.

A regra vale também para registros manuais. Registros antigos incompatíveis com a função ficam fora dos totais, preservados no histórico com o motivo. Promoções e transferências posteriores não mudam a função usada para uma falta antiga.

## Regra de contagem

Cada combinação de **colaborador + data + tipo de checklist** representa uma falta. Várias ações sobre a mesma combinação contam uma vez e aparecem juntas no histórico. Saída e retorno no mesmo dia contam duas faltas. Os tipos disponíveis são saída, retorno, empilhadeira, paleteira, segurança e outro.

O ano é determinado pela data da falta, independentemente da criação, vencimento ou conclusão da tarefa. Concluir/reabrir a ação, encerrar o GEROT ou corrigir seu percentual não apaga a falta. O cartão **Com ações abertas** conta faltas que ainda têm pelo menos uma ação aberta, enquanto os demais cartões e a tabela mantêm o total anual. Os filtros de colaborador e mês detalham o histórico; a tabela e os cartões mostram o ano completo das origens habilitadas nas configurações, respeitando as permissões de acesso e o escopo de ativos dos acompanhamentos anual e mensal.

Para corrigir um lançamento, abra a tarefa e use **Desconsiderar registro**, informando o motivo. O registro original, autor e motivo permanecem na tarefa e na atividade. Depois, registre os dados corretos. Uma tarefa com histórico de ocorrências permanece em seu plano e não pode voltar à Entrada pessoal. Não é permitido excluir tarefas ou colaboradores que sustentem esse histórico.

## Acesso e implantação

O módulo está disponível para os perfis que acompanham colaboradores e para Frota. O acesso da Frota ao módulo não amplia suas permissões para editar o cadastro de RH. DU consulta seus colaboradores; AZ consulta os seus; RH e administradores têm a visão permitida de ambas as áreas. As ocorrências desses colaboradores aparecem no módulo mesmo quando sua ação pertence a um plano privado de outra área. Nesse caso, só a ocorrência e a referência numérica da ação são mostradas: título, nome do plano, GEROT e link para os detalhes continuam protegidos pelas permissões de tarefas.

A fila de identificação, registro em lote e alterações em tarefas continuam exigindo acesso à ação de origem; justificar a contagem de uma ocorrência usa a permissão do próprio módulo e o escopo de colaboradores. Mecânicos e visitantes não têm acesso ao módulo. CPF e outros dados pessoais do cadastro não são exibidos.

Antes de executar a versão atualizada, rode `bundle exec rails db:migrate`. As migrações criam a tabela independente de ocorrências, adicionam a categoria das justificativas, permitem registrar placas SPOT sem vínculo com colaborador e adicionam a visibilidade compartilhada dos planos de origem (`checklist_tracking_visible`). Não transformam sugestões históricas em faltas confirmadas.

Validação:

```sh
PARALLEL_WORKERS=1 bundle exec rails test test/services/checklist_tracking test/controllers/checklist_occurrences_controller_test.rb test/controllers/tasks_controller_test.rb test/controllers/plan_gerots_test.rb test/models/task_test.rb
bundle exec rails assets:precompile
```
