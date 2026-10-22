# Assistente pessoal de IA

O botão **Assistente IA** aparece para usuários autenticados no canto inferior direito. Em telas com o gravador de reuniões, aparece acima dele. Os painéis se minimizam mutuamente sem interromper uma gravação. No celular, assistente e gravador usam botões de ícone, deixando o botão Entrada livre no centro.

Cada conta tem uma conversa persistida no banco, independente do navegador e das conversas de outras contas. **Limpar conversa** exclui o histórico daquela conta, cancela propostas pendentes e descarta respostas anteriores ainda em execução. Os registros já criados e sua auditoria são mantidos. O botão **Perguntar à IA** pertence ao fluxo público por matrícula e nascimento e não aparece para contas logadas; esse fluxo público não executa ações.

## Consultas disponíveis

O catálogo de funções enviado ao Gemini é montado para o perfil atual. O servidor confere novamente a autorização em cada chamada, inclusive quando o modelo tenta chamar uma função não anunciada. A identidade e o setor usados vêm da conta autenticada; parâmetros ou texto da pergunta não alteram permissões.

| Área | Consultas |
| --- | --- |
| Tarefas e planos | Tarefas pessoais, abertas, vencidas e concluídas; responsáveis, prazos, busca e resumo de planos. |
| Financeiro | Lançamentos, fornecedores, categorias, centros de custo, valores por emissão ou vencimento, totais, metas do mês, desvios por meta, possíveis ofensores e comparação com o mês anterior. Vencimento não comprova pagamento ou atraso. |
| RH e colaboradores | Diretório autorizado, cargos, turnos, setores, histórico de funções, últimas revisões dos fechamentos, prévias de variável e feedbacks do Ciclo de Gente. Não envia CPF ou nascimento nessas consultas. |
| DU | Mapas, caixas, PDVs, recargas e devolução; consumo Gasola, médias, metas, emissões e comparações por motorista/placa. |
| Armazém | Indicadores e remuneração por cargo no período e turno, pelos mesmos relatórios do dashboard AZ. |
| Folgas e PCD | Escala pessoal/equipe, folga, DSR e férias; PCD SALAS salvo ou prévia, equipes, placas, salas e horários. |
| Frota | Disponibilidade diária e média por mês/período, cobertura dos registros, dias abaixo da meta, motivos, observações, cadastro de placas, dimensionamento, pneus no limite de recape/instalados e eventos de stress test. |
| GEROT | Rotinas autorizadas, indicadores, metas, resultados calculados, preenchimentos por data e pendências. A consulta não gera valores faltantes. |
| Atas | Busca, resumo, decisões e pendências das atas autorizadas. Não consulta áudio nem conversas do assistente. |
| Documentos e recursos | Catálogo de padrões, LUPs, matrizes, rotogramas e distribuição de placas no pátio. Não lê PDFs/anexos nem inventa procedimentos pelo título. |
| Administração | Contas, setores e perfis; configuração, consumo e cotas de IA, incluindo uso por colaborador. Não retorna credenciais ou conteúdo de conversas privadas. |

As permissões usam `User`, `NavbarHelper` e os escopos dos registros. Financeiro respeita os setores orçamentários; o perfil Financeiro, como na tela, pode consultar todos esses setores. O diretório respeita os setores de colaboradores permitidos e suas vigências. GEROTs e planos usam seus escopos `visible_to`; tarefas usam `accessible_to`, preservando entradas pessoais e as restrições dos mecânicos. Consultar um plano não libera suas atas: elas exigem criação, colaboração, propriedade do plano ou administração. Checklists seguem o histórico da tela: próprios para usuários comuns, gerais para administradores e supervisores.

Administradores podem consultar os módulos de todos os setores. As conversas pessoais e as credenciais continuam privadas. Mecânicos mantêm seu fluxo de tarefas atribuídas e Entrada pessoal, além dos checklists próprios e recursos públicos; o setor gravado no cadastro não amplia seu acesso.

Resultados são paginados em 20 registros e incluem os totais completos. Os links dos registros são gerados pelo Rails.

## Análises por período

Perguntas como **“Qual a média de carros disponíveis em outubro?”** usam `fleet_analysis`, com mês civil (`month: YYYY-MM`) ou intervalo (`from/to`, até 366 dias de diferença). A média é calculada no servidor sobre todos os retratos diários cadastrados até hoje, com o mesmo peso por dia, independentemente da paginação. Dias sem registro e futuros ficam fora do denominador; o resultado informa dias registrados, ausentes e futuros, período observado e se é parcial. Um retrato cadastrado sem veículos participa com contagem zero. Sem retratos no período, a média é indisponível.

O relatório separa disponíveis, em troca, indisponíveis e rotas especiais; inclui média do dimensionamento acordado, mínimo/máximo, dias abaixo da meta e motivos de indisponibilidade em veículos-dia. Uma placa retirada depois do dia consultado continua entrando naquele histórico, usando `Plate.active_on?`, como na consulta diária. São retratos salvos, possivelmente editados, e não uma média de todas as mudanças ao longo de cada dia. `fleet_status` continua consultando uma data exata e distingue o total do retrato (`fleet_total`) da quantidade filtrada (`filtered_total`/`total`).

Perguntas como **“Quero um panorama financeiro de setembro, comparando gastos com metas e possíveis ofensores”** usam `financial_analysis`. Em uma consulta, o servidor reúne total por emissão no mês civil, categorias ordenadas por gasto, fornecedores e lançamentos de maior valor, comparação com o mês anterior e todas as metas cadastradas naquele mês, ordenadas pelo excesso em reais. Cada meta informa realizado, saldo, excesso, percentual utilizado e até cinco categorias, cinco fornecedores e três lançamentos que contribuíram para o gasto; os rankings gerais mostram até dez fornecedores e dez lançamentos. Categorias e metas têm páginas de 20 registros, com contadores e totais calculados sobre o conjunto completo.

Metas sobrepostas não são somadas. Gastos de categorias sem meta são identificados e continuam sendo analisados mesmo sem qualquer orçamento cadastrado. Metas existentes aparecem mesmo sem lançamentos. Meses sem registros anteriores não viram uma base zero para calcular variação percentual, e metas de outro mês não são reutilizadas. Os contribuintes de maior valor são possíveis ofensores, sem comprovar a causa do desvio. Valores lançados não comprovam pagamento.

Sem setor explícito na pergunta, a análise financeira usa todos os setores autorizados pela conta, como na tela; não restringe administradores ou contas de Financeiro ao setor do cadastro. `financial_summary` e `list_invoices` também aceitam `month`, além dos intervalos explícitos. O mês solicitado é preservado em todas essas consultas. Sem ano informado, o assistente usa o atual, salvo contexto explícito, e informa o ano considerado. As funções analíticas são somente leitura e conferem novamente as permissões a cada chamada.

## Criação de tarefas e planos com confirmação

Usuários ativos que podem criar tarefas nas telas do app podem solicitar ao assistente:

- Uma tarefa na **Entrada pessoal**, ou em um bucket de um plano acessível.
- Título, descrição, responsáveis por conta do app, início, prazo, checklist e lembrete de vencimento.
- Um novo plano de ação com descrição, setor, visibilidade e até dez tarefas iniciais em **A Fazer**. Os buckets padrão do app também são criados.

Contas comuns criam planos no próprio setor; administradores podem escolher qualquer setor. Mecânicos mantêm as consultas e o fluxo de tarefas atribuídas, sem as funções de criação do assistente. A atribuição de responsáveis usa contas ativas do app, como o formulário de tarefas; não utiliza colaboradores identificados apenas por matrícula. A Entrada permanece privada mesmo com outros responsáveis atribuídos: eles veem a tarefa quando ela é movida para um plano.

As funções `prepare_task` e `prepare_plan` apenas preparam prévias. O usuário confere todos os dados, inclusive destino e visibilidade, e escolhe **Confirmar criação**, **Ajustar** ou **Cancelar**. Nenhuma tarefa, plano, Entrada ou notificação é criado durante a preparação. Responder “sim” na conversa não executa a ação. `action_options` localiza buckets e contas ativas; `pending_actions` permite consultar os dados da proposta atual para ajustá-la, sem enviar o token de confirmação ao modelo.

Cada proposta vale por **30 minutos** e pertence exclusivamente à conta autenticada. A confirmação exige o token da prévia e confere novamente perfil, setor, acesso ao plano/bucket, responsáveis ativos e os dados mostrados. Mudanças no destino ou na visibilidade exigem nova proposta. Uma nova resposta com propostas cancela as anteriores ainda pendentes. Até três propostas podem ser preparadas por resposta.

Sem destino solicitado, o padrão é a Entrada pessoal; sem responsável, a própria conta. Sem prazo solicitado, não há prazo. Uma data sem hora vence às **23:59:59 em Brasília**. Lembretes são ativados somente quando solicitados com prazo e seguem as notificações de vencimento existentes do app. Novos planos são restritos ao setor por padrão; torná-los públicos deve ser solicitado explicitamente e aparece na prévia.

Confirmações usam transação e bloqueio no banco. Repetir um clique ou requisição retorna o resultado já registrado sem criar cópias. A criação de um plano e suas tarefas é atômica: uma falha desfaz todo o conjunto. Notificações e checklists usam o fluxo normal dos modelos.

A tabela `ai_action_requests` registra conta autora, tipo, dados aprovados, prévia, estado, validade, horário de execução e IDs/links do resultado. Atividades de tarefas registram a origem `ai_assistant` e o ID da proposta. Essa auditoria permanece após limpar a conversa, com o vínculo à mensagem removido. Não é incluída nas estatísticas administrativas de consumo nem permite consultar conversas de outras contas.

Exemplos: “Crie uma tarefa para inspecionar os pneus amanhã às 14h, com lembrete”, “No plano Revisão de Frota, crie uma tarefa para conferir o estepe e atribua à Ana”, “Prepare um plano de inspeção mensal com tarefas para pressão, sulcos e estepe”.

## Montagem de automações pela conversa

O assistente monta regras do módulo **Automações** com `automation_options`, `configure_automation` e `prepare_automation`. O passo a passo está disponível como sugestão no assistente. Na central, o painel recolhível **Crie uma automação com suas palavras** permite enviar uma descrição diretamente. A IA usa origens/ações do catálogo real, localiza registros permitidos e pergunta um dado por vez, preservando as escolhas privadas por até duas horas. Respostas curtas completam a montagem atual; mudar perfil/setor, expirar o estado ou limpar a conversa a descarta.

Também aceita a regra inteira em texto livre no chat ou no campo **Crie uma automação com suas palavras** da central. **Gerar prévia com IA** envia a descrição ao assistente. Um pedido completo pode usar `prepare_automation` diretamente após localizar os IDs autorizados; perguntas adicionais são feitas somente para informações ausentes ou ambíguas.

Regras financeiras aceitam uma lista `filters.budget_category_ids`. O assistente pode reunir várias categorias em um único indicador, como um pacote de manutenção, mantendo todas na prévia. Adicionar/remover categorias exige enviar a lista final completa; listas repetidas são normalizadas. Categorias são autorizadas individualmente e nenhuma é inferida apenas pelo nome do indicador. As regras antigas com filtro singular continuam aceitas.

Uma regra completa vira uma proposta `create_automation` com configuração e estado de ativação explícitos. O padrão é **Salvar automação pausada**; ativação escolhida pelo usuário usa **Salvar e ativar automação**. São os mesmos controles de ajustar, cancelar, validade de 30 minutos, tokens de confirmação apenas no cliente, isolamento por conta e idempotência das outras propostas. Confirmar cria somente a regra, sem executar seus efeitos naquele momento. Permissões e nomes de destinos são revalidados ao confirmar. A confirmação é auditada em `AiActionRequest`, e o resultado aponta para a regra criada.

A IA pode simular a consulta sem escrever. Falta de dados ou de GEROT aberto é relatada como indisponível; números da simulação podem mudar antes da execução e não são fixados pela confirmação. A ferramenta não executa nem altera regras existentes. O motor posterior de agendamento não chama IA. Consulte [automacoes.md](automacoes.md) para filtros, ações, períodos e proteções.

## Atualização e conclusão de tarefas

`task_details` consulta os dados atuais da tarefa autorizada. `prepare_task_update` prepara mudanças somente nos campos solicitados: título, descrição, início, prazo, responsáveis, lembrete e situação. A prévia mostra **Antes** e **Depois**, com **Confirmar alterações**, **Ajustar** e **Cancelar**. Mensagens de texto não confirmam uma alteração.

Os campos omitidos são preservados. Mudar apenas o prazo não remove responsáveis, etiquetas ou checklist. Remover o prazo também desativa o lembrete, mostrado na comparação. Conclusão e reabertura usam situações explícitas, sem alternância em requisições repetidas; a conclusão grava `completed_at`, e a reabertura o remove. Tarefas recorrentes mantêm o fluxo existente de próxima ocorrência, com aviso na prévia.

O acesso usa `Task.accessible_to`, como a edição normal do app. Mecânicos podem atualizar tarefas atribuídas e da própria Entrada, sem ganhar acesso a tarefas de outros mecânicos ou à criação. Administradores continuam sem acesso às Entradas pessoais alheias. A atribuição seleciona contas ativas, e o autor registrado é sempre a conta autenticada.

A confirmação bloqueia a tarefa na transação e compara os dados atuais com o estado usado na prévia, inclusive responsáveis e versão. Se alguém editar a tarefa, movê-la ou alterar seus acessos, a proposta não sobrescreve a edição: é preciso consultar novamente e preparar outra. As atividades registram autor, origem do assistente e proposta para cada campo alterado, incluindo responsáveis adicionados/removidos. O quadro recebe as atualizações pelo fluxo normal de transmissão do app.

Exemplos: “Adie esta tarefa para sexta às 15h”, “Adicione a Ana aos responsáveis e mantenha os demais”, “Desative o lembrete”, “Conclua esta tarefa”, “Reabra a tarefa de conferir os pneus”.

Excluir registros, movimentar tarefas, alterar recorrência/checklist/etiquetas e registrar manutenção diretamente continuam disponíveis pelas telas correspondentes.

## Atalhos da tela aberta

O painel mostra o registro usado como referência e atalhos conforme a tela:

- Plano: **Resumir plano**, **Ver pendências** e **Criar tarefa** (quando permitido).
- Tarefa: **Resumir tarefa**, **Alterar prazo** e **Concluir/Reabrir tarefa**.
- Veículo: **Ver pendências**, **Ver disponibilidade** e **Ver pneus**, conforme acesso aos módulos.

O usuário pode remover o contexto pelo botão ao lado do nome. Cada pergunta guarda somente o tipo e o ID do registro em `ai_messages.page_context`, evitando que uma navegação ou outra aba troque a referência de uma pergunta já enfileirada. Não é enviado o HTML da página.

O servidor valida a referência ao receber a pergunta e novamente no worker. Abrir uma tela ou enviar um ID manualmente não amplia permissões. Se o acesso tiver sido revogado, o modelo recebe um aviso de contexto indisponível. As funções continuam exigindo autorização em cada consulta e proposta.

## Resumo do dia

A pergunta **“O que tenho para o dia de hoje?”** chama `daily_briefing`, também sugerida na abertura do assistente. O foco padrão é o setor da conta; administradores podem pedir outro setor ou um panorama de todos (`all`). A data é a de hoje no fuso configurado pelo app.

O resumo reúne:

- Tarefas atribuídas ao usuário e sua Entrada pessoal: prazos vencidos, do dia e dos próximos sete dias. Tarefas de outras entradas não aparecem. Vencidas de hoje também entram no contador de hoje; a lista não duplica registros.
- GEROTs abertos/vigentes do setor: indicadores com desvio no resultado atual e preenchimentos previstos para hoje ainda pendentes. Considera a frequência diária, semanal ou mensal. Os cálculos podem ser parciais.
- Financeiro autorizado: gasto lançado no mês civil, vencimentos do dia, meta, realizado e saldo de cada meta. Saldo negativo indica excesso. Categorias podem se sobrepor entre metas, portanto os saldos não são somados como um orçamento único.
- Frota: veículos indisponíveis ou em troca, motivos/observações, dimensionamento, pneus no limite de recape, consumo abaixo da meta, movimentos de stress test e placas sem mapa de rodagem no mês. Ausência de mapa não comprova veículo parado.
- DU: indicadores do fechamento, escalas da equipe, PCD e consumo, conforme as permissões.
- Armazém: indicadores e resultados do fechamento AZ, GEROT e quadro de colaboradores.
- RH e Planejamento: quadro/funções de colaboradores, entradas em função, início pendente, escala e prioridades de indicadores, tarefas e orçamento autorizado. Planejamento também consulta indicadores DU permitidos.
- Segurança: pneus, rodagem, consumo, escala e indicadores/orçamento autorizados.
- Financeiro: metas e gastos dos setores autorizados, vencimentos, indicadores e agenda pessoal.

Módulos sem acesso são omitidos do resumo. Registro ou integração ausente é informado como indisponível, sem presumir zero problemas. Sem meta cadastrada não há saldo estimável. O resumo mantém as janelas de cada fonte: financeiro civil, DU/consumo de 21 a 20 e AZ de 19 a 18. Não representa confirmação de pagamento ou presença no trabalho.

Exemplos: “Resuma meu dia”, “Quanto sobra da meta de manutenção deste mês?”, “Quais veículos e pneus precisam de atenção?”, “Quais indicadores estão pendentes hoje?”, “Resuma o dia do Armazém” (para administradores).

## Preparação

1. Execute `bin/rails db:migrate`.
2. Configure `GEMINI_API_KEY` no servidor. A chave não é enviada ao navegador.
3. Mantenha o worker Sidekiq ativo em produção (`bundle exec sidekiq`), com Redis configurado, como nas atas de reuniões. Em desenvolvimento, o Active Job usa o adaptador configurado no Rails.
4. O modelo é o selecionado em **Admin → Configurações de IA**, com alternativas de modelo em caso de indisponibilidade ou limite.

As consultas são processadas em segundo plano e o painel acompanha a resposta. Cada conta pode ter uma consulta em andamento e até 20 novas perguntas por janela de uma hora; limpar o histórico não reinicia esse limite. Consultas sem conclusão após cinco minutos são liberadas para nova tentativa.

A integração usa a API Interactions com funções permitidas explicitamente e `store: false`. O histórico do app fica no banco local. Apenas as perguntas recentes e os resultados das funções autorizadas da rodada são enviados ao Gemini; respostas antigas não são reenviadas. Perguntas e prévias usam texto simples. Respostas do assistente aceitam formatação básica de parágrafos, negrito, ênfase, títulos, listas e código, inclusive no histórico já salvo. A formatação cria elementos permitidos com nós de texto, sem interpretar HTML, links ou controles fornecidos pelo modelo; os links de fontes e botões de ação continuam sendo gerados pelo app. Não são habilitados SQL gerado pelo modelo, execução de código, acesso livre à rede ou execução de ações pelo modelo. A gravação dos registros usa endpoints autenticados separados e depende do botão de confirmação.

## Falhas e tempo de espera

O navegador acompanha o job em segundo plano. Cada chamada ao Gemini tem limite de 45 segundos, respeitando um orçamento de 150 segundos para as chamadas da consulta. Timeout, falha de conexão e HTTP 404/408/429/5xx permitem tentar outro modelo, com no máximo três candidatos por etapa. Falhas de autenticação ou formato não são repetidas em outros modelos.

Quando a consulta falha, o painel distingue demora do Gemini, conexão, cota, autenticação/configuração, resposta inválida, limite de etapas e falha interna. A mensagem inclui uma referência `IA-...`, também registrada em um evento `ai_assistant_failure` nos logs do worker, com classe da exceção, modelo, função em execução, status HTTP e linhas do código do app quando disponíveis. Corpos HTTP, mensagens brutas de exceção, perguntas e credenciais não entram nesse diagnóstico. Os metadados de cada tentativa continuam em `AiApiRequest`.

Para uma avaliação financeira em PDF com período fixo e sem depender do Gemini, use o [relatório gerencial financeiro](relatorio_financeiro.md) do dashboard.

## Validação

`PARALLEL_WORKERS=1 bin/rails test test/controllers/ai_assistants_controller_test.rb test/controllers/ai_assistant_actions_controller_test.rb test/controllers/ai_assistant_task_updates_test.rb test/services/ai_assistant_actions_test.rb test/services/ai_assistant_page_context_test.rb test/services/ai_assistant_tools_test.rb test/services/ai_assistant_queries_test.rb test/services/ai_assistant_analytics_test.rb test/services/ai_assistant_daily_briefing_test.rb test/jobs/ai_assistant_job_test.rb test/jobs/ai_assistant_analytics_job_test.rb test/jobs/ai_assistant_task_context_job_test.rb`

Os testes cobrem autenticação, isolamento entre contas, matriz de setores/perfis, bloqueio por IDs e chamadas de funções não anunciadas, paginação, saldos e metas sobrepostas, resumo diário, ausência de dados/integrações, consultas sem escrita, privacidade das conversas, continuidade de funções, cancelamento e falhas do provedor. Também cobrem prévias sem gravação, confirmação explícita, repetição de requisições, expiração, revalidação de permissões/dados, rollback de planos e auditoria após limpar. As chamadas externas são simuladas nos testes.

Os cenários de navegador usam `test/browser/ai_assistant_actions_setup.rb` / `ai_assistant_actions_test.cjs` para criação e `test/browser/ai_assistant_updates_setup.rb` / `ai_assistant_updates_test.cjs` para atualização, contra um servidor Rails de testes com assets. Verificam prévias em desktop/celular e temas claro/escuro, gravador, conteúdo escapado, ajuste, cancelamento, confirmação real no banco, persistência, links, contexto por aba, passagem da janela da tarefa ao assistente, comparação antes/depois e bloqueio de edição desatualizada, sem chamadas ao Gemini.
