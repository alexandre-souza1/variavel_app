# Central de automações

Acesse **Automações** no menu principal ou a partir da lista de GEROTs. Cada regra combina uma origem, filtros, período, cálculo, condição, ação e agendamento. Nenhuma regra de combustível é fixa no código. Esta versão oferece três conectores de origem e três ações combináveis; novos conectores entram no catálogo sem criar outro módulo.

**Nova automação** e **Editar regra** abrem um painel lateral, largo no computador e em tela inteira no celular. A prévia e os erros de validação aparecem no próprio painel, preservando os campos. Fechar e reabrir o mesmo formulário mantém o rascunho enquanto a página permanecer aberta. Salvar uma nova regra fecha o painel e atualiza a lista; editar retorna aos detalhes da regra. A página de detalhes mantém a configuração e o histórico. Os endereços diretos de criação/edição continuam disponíveis.

## Recursos disponíveis

| Origem | Filtros | Cálculos |
| --- | --- | --- |
| Financeiro | Setor e uma ou várias categorias, dentro das permissões do responsável | Soma, média e quantidade de lançamentos |
| Tarefas | Pendentes/vencidas/concluídas, plano e somente minhas | Quantidade |
| Disponibilidade | Situação dos veículos e data (hoje/ontem) | Quantidade |

As condições aceitam sempre, maior/menor, maior/menor ou igual e igualdade. O valor é comparado como decimal. Não há código, SQL ou requisições HTTP configuráveis.

O seletor financeiro usa a mesma caixa de seleção das tarefas, com busca, múltiplas categorias e remoção individual das seleções. Assim, um indicador **Pacote Manutenção** pode receber a soma de manutenção de caminhões, empilhadeiras e outras categorias escolhidas. A prévia identifica a seleção completa. Nenhuma categoria marcada significa todas as categorias permitidas (respeitando o setor, quando escolhido). IDs repetidos são removidos, e cada lançamento entra uma única vez, mesmo quando tem várias notas ou quando outro lançamento tem o mesmo valor. Soma, média e contagem usam o mesmo conjunto de lançamentos. Se qualquer categoria perder acesso, a regra inteira é bloqueada, preservando o indicador em vez de lançar um total parcial.

O filtro JSON usa `budget_category_ids`, uma lista de até 200 IDs. Regras e propostas antigas com `budget_category_id` continuam funcionando; editar a seleção ou preparar pela IA usa o formato de lista. Não é necessária migration adicional para a seleção múltipla.

| Ação | Comportamento |
| --- | --- |
| Preencher GEROT | Localiza o GEROT aberto do modelo na data-base e atualiza a célula do período |
| Criar tarefa | Entrada pessoal ou bucket permitido; responsável pela regra é criador e atribuído; prazo opcional |
| Enviar aviso | Notificação para o responsável no app; usa o fluxo de push existente quando disponível |

Tarefas e avisos aceitam `{{valor}}`, `{{periodo}}` e `{{automacao}}` no título e descrição. Os textos são escapados nas telas. Uma regra emite no máximo uma tarefa ou aviso por período consultado; em **Todo o histórico**, uma única vez. Alterar o resultado ou repetir a execução no mesmo período não duplica a ação. Alterar uma regra não apaga seus registros anteriores.

## Períodos e dados

Hoje, ontem, semana atual/anterior, mês atual/anterior e todo o histórico. Períodos atuais são consultados até a data-base. Semanas começam na segunda-feira. O financeiro usa **data de emissão**, soma despesas lançadas e não confirma pagamento. Sem lançamentos financeiros, a ação é ignorada, preservando o destino. Tarefas usam prazo para pendências/vencidas e data de conclusão para concluídas. Todo o histórico também inclui pendências sem prazo. Disponibilidade ausente é registrada como falta de dados, não como zero veículos.

Para GEROT, período diário exige indicador diário, semanal exige semanal, mensal exige mensal. Isso evita repetir acumulados mensais em colunas diárias que seriam somadas pelo GEROT. A célula usa o dia de referência configurado no GEROT, inclusive último dia do mês. O cálculo considera o período civil escolhido, mesmo quando o GEROT começa no meio do período; a prévia mostra as datas exatas. Se não houver GEROT aberto, célula esperada, indicador selecionado ou houver períodos abertos sobrepostos, a execução registra o motivo e não escreve.

Valores manuais são protegidos por padrão. Substituí-los exige habilitar a opção na regra. Uma edição manual no GEROT remove a identificação de automação da célula, mesmo que confirme o mesmo valor. Outra automação nunca substitui uma célula já preenchida por uma regra diferente. Só uma regra por indicador/modelo pode estar ativa. Repetições atualizam o valor calculado na mesma célula, sem adicioná-lo novamente. O histórico normal do GEROT identifica a automação e preserva as regras de tarefas por desvio.

## Permissões e operação

Usuários ativos que não sejam mecânicos acessam o módulo. Origens seguem a liberação do menu, e registros seguem os escopos existentes (`Invoice.visible_to`, `Task.accessible_to`, `Routine.visible_to`). Cada usuário vê suas regras; admins podem consultar e operar todas. A execução sempre usa as permissões atuais do responsável original, mesmo iniciada por admin. Aposentadoria ou perda de acesso bloqueia execuções. Pausar continua possível quando a configuração perde validade.

Regras novas e alteradas pela tela ficam **pausadas**. Pela IA, o usuário pode escolher a ativação explicitamente, destacada na prévia. A prévia consulta dados sem criar registros, Entrada, histórico ou notificações. **Executar agora** executa a regra salva, inclusive pausada. Para agendar pela tela, ative a regra depois de conferir sua prévia. Datas usam o fuso **Brasília**. Frequências: manual, a cada hora, diária, semanal e mensal. Dias 29–31 se ajustam ao fim do mês.

## Montagem com o assistente

Para iniciar uma conversa guiada, use a sugestão no assistente pessoal ou peça diretamente: “Quero montar uma automação passo a passo”. O modelo consulta `automation_options` para localizar as opções reais e permitidas, guarda as escolhas com `configure_automation` e pergunta somente o próximo dado necessário. Não é necessário preencher o formulário manualmente.

A central também oferece o painel recolhível **Crie uma automação com suas palavras**, inicialmente minimizado: um campo de até 1800 caracteres e o botão **Gerar prévia com IA**. É possível descrever a regra inteira ali ou diretamente no chat. Quando o texto contém os dados necessários, o assistente resolve as opções autorizadas e prepara a prévia diretamente, sem exigir a montagem em etapas. Se algo estiver faltando ou ambíguo, pergunta apenas essa parte. O pedido é uma nova regra e não deve herdar escolhas de uma montagem anterior. A confirmação da prévia continua obrigatória.

Exemplo de pacote: “Some as manutenções de caminhões e empilhadeiras do mês e preencha o indicador Pacote Manutenção, todo dia às 8h”. A IA localiza as categorias e monta uma única lista. O nome do indicador não determina quais categorias fazem parte dele: se o usuário disser somente “pacote manutenção”, o assistente pergunta quais incluir. Adições/remoções substituem a lista completa, preservando as demais escolhas da montagem.

A montagem parcial fica em `ai_conversations.automation_setup`, privada da conta, por até duas horas após a última escolha. A cada pergunta o worker recebe esse estado validado para interpretar respostas curtas, como “às 8h”. Mudanças de perfil/setor, expiração ou **Limpar conversa** descartam o estado. Um worker de uma pergunta antiga não consegue regravar a montagem depois de limpar ou iniciar uma nova pergunta. Categorias, indicadores, planos e buckets são revalidados contra as permissões atuais.

Quando completa, `prepare_automation` prepara uma proposta `create_automation` em `AiActionRequest`. A simulação consulta os dados atuais e não escreve; ausência de dados/destino é informada como indisponível. A prévia persistente descreve configuração, filtros, período, condição, destino, proteção de valores manuais, agendamento e estado de ativação. Os totais da simulação não entram na comparação de confirmação, pois a confirmação cria a regra e não fixa um resultado financeiro. Renomear destinos ou perder permissões exige uma nova prévia.

O botão **Salvar automação pausada** é o padrão. **Salvar e ativar automação** aparece quando a ativação foi escolhida explicitamente. A proposta vale por 30 minutos e pode ser ajustada ou cancelada. “Sim” ou “pode fazer” em texto não confirmam. Confirmar salva a regra uma única vez, registra a auditoria existente da proposta e retorna **Abrir automação**. Nunca preenche GEROT, cria tarefas ou envia avisos naquele instante; ações são realizadas pelo agendamento ou por **Executar agora** na tela. Confirmação e cancelamento limpam a montagem parcial, e ajustes substituem propostas pendentes anteriores.

A montagem usa o Gemini e as cotas de conversa já existentes. A execução posterior das regras continua independente de IA. A função atende contas autenticadas com acesso ao módulo; o chat público por matrícula/nascimento não ganha ações administrativas.

O worker Sidekiq existente despacha regras vencidas a cada minuto (`Automations::Scheduler`), desde o início até o encerramento do processo. Não exige outro dyno, biblioteca de cron ou chamadas à IA. Precisa do worker ativo. Múltiplos workers são serializados por bloqueio da regra e nova conferência do vencimento; tarefas/avisos também têm chave única de efeito no banco. Se o worker ficar indisponível, executa a consulta com os dados e período atuais ao retomar, sem reconstruir períodos perdidos. Ações e histórico são gravados na mesma transação; falhas desfazem a ação e deixam um registro de falha com mensagem genérica. Os logs registram somente ID da regra e classe de erro.

A página mostra as últimas 100 regras e as últimas 50 execuções; registros anteriores permanecem no banco. Pausar mantém todo o histórico. Não existe exclusão de regras com auditoria nesta versão.

## Estrutura para expansão

- `Automations::Catalog`: registro de origens, operações e ações.
- `Sources::*`: validação de filtros/permissões e consulta, retornando valor, quantidade, disponibilidade e nota.
- `Actions::*`: validação de destino, prévia sem escrita e execução dentro de transação.
- `Period`, `Configuration`, `Preview`, `Runner`: funções comuns de período, validação, prévia, condição, auditoria e duplicidade.
- `AutomationRule`, `AutomationRun`: configurações e auditoria persistentes.

Adicionar uma origem exige seu adaptador, liberação no catálogo, campos no formulário e verificações de permissão. Adicionar uma ação segue o mesmo contrato e define sua política de repetição. A execução das regras não depende do Gemini. Gatilhos nesta versão são manuais ou de horário; eventos de alteração de registros ainda não estão incluídos. O assistente monta novas regras e não altera, exclui, executa ou alterna a ativação de regras existentes.

## Validação local

`PARALLEL_WORKERS=1 bin/rails test test/services/automations_test.rb test/models/automation_rule_test.rb test/controllers/automation_rules_controller_test.rb`

O fluxo de navegador tem preparação separada no banco de testes em `test/browser/automations_setup.rb`, execução em `test/browser/automations_test.cjs` e limpeza em `test/browser/automations_cleanup.rb`. Não executar a preparação em produção.

Migrations: `20261016180000_create_automation_module.rb` e `20261016190000_enable_ai_automation_drafts.rb`. A implantação usa o release de migrations já existente. Nenhuma regra é ativada ou criada automaticamente pelas migrations.
