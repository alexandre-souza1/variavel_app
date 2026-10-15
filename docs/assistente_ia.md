# Assistente pessoal de IA

O botão **Assistente IA** aparece para usuários autenticados no canto inferior direito. Em telas com o gravador de reuniões, aparece acima dele. Os painéis se minimizam mutuamente sem interromper uma gravação. No celular, assistente e gravador usam botões de ícone, deixando o botão Entrada livre no centro.

Cada conta tem uma conversa persistida no banco, independente do navegador e das conversas de outras contas. **Limpar conversa** exclui o histórico daquela conta e descarta respostas de consultas anteriores ainda em execução.

## Consultas disponíveis

O catálogo de funções enviado ao Gemini é montado para o perfil atual. O servidor confere novamente a autorização em cada chamada, inclusive quando o modelo tenta chamar uma função não anunciada. A identidade e o setor usados vêm da conta autenticada; parâmetros ou texto da pergunta não alteram permissões.

| Área | Consultas |
| --- | --- |
| Tarefas e planos | Tarefas pessoais, abertas, vencidas e concluídas; responsáveis, prazos, busca e resumo de planos. |
| Financeiro | Lançamentos, fornecedores, categorias, centros de custo, valores por emissão ou vencimento, totais, metas do mês e saldo por meta. Vencimento não comprova pagamento ou atraso. |
| RH e colaboradores | Diretório autorizado, cargos, turnos, setores, histórico de funções, últimas revisões dos fechamentos, prévias de variável e feedbacks do Ciclo de Gente. Não envia CPF ou nascimento nessas consultas. |
| DU | Mapas, caixas, PDVs, recargas e devolução; consumo Gasola, médias, metas, emissões e comparações por motorista/placa. |
| Armazém | Indicadores e remuneração por cargo no período e turno, pelos mesmos relatórios do dashboard AZ. |
| Folgas e PCD | Escala pessoal/equipe, folga, DSR e férias; PCD SALAS salvo ou prévia, equipes, placas, salas e horários. |
| Frota | Disponibilidade, motivos, observações, cadastro de placas, dimensionamento, pneus no limite de recape/instalados e eventos de stress test. |
| GEROT | Rotinas autorizadas, indicadores, metas, resultados calculados, preenchimentos por data e pendências. A consulta não gera valores faltantes. |
| Atas | Busca, resumo, decisões e pendências das atas autorizadas. Não consulta áudio nem conversas do assistente. |
| Documentos e recursos | Catálogo de padrões, LUPs, matrizes, rotogramas e distribuição de placas no pátio. Não lê PDFs/anexos nem inventa procedimentos pelo título. |
| Administração | Contas, setores e perfis; configuração, consumo e cotas de IA, incluindo uso por colaborador. Não retorna credenciais ou conteúdo de conversas privadas. |

As permissões usam `User`, `NavbarHelper` e os escopos dos registros. Financeiro respeita os setores orçamentários; o perfil Financeiro, como na tela, pode consultar todos esses setores. O diretório respeita os setores de colaboradores permitidos e suas vigências. GEROTs e planos usam seus escopos `visible_to`; tarefas usam `accessible_to`, preservando entradas pessoais e as restrições dos mecânicos. Consultar um plano não libera suas atas: elas exigem criação, colaboração, propriedade do plano ou administração. Checklists seguem o histórico da tela: próprios para usuários comuns, gerais para administradores e supervisores.

Administradores podem consultar os módulos de todos os setores. As conversas pessoais e as credenciais continuam privadas. Mecânicos mantêm seu fluxo de tarefas atribuídas e Entrada pessoal, além dos checklists próprios e recursos públicos; o setor gravado no cadastro não amplia seu acesso.

Resultados são paginados em 20 registros e incluem os totais completos. Os links dos registros são gerados pelo Rails. A versão atual realiza somente consultas.

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

A integração usa a API Interactions com funções permitidas explicitamente e `store: false`. O histórico do app fica no banco local. Apenas as perguntas recentes e os resultados das consultas autorizadas da rodada são enviados ao Gemini; respostas antigas não são reenviadas. Textos são renderizados como texto simples. Não são habilitados SQL gerado pelo modelo, execução de código, acesso livre à rede ou alteração de registros.

## Validação

`PARALLEL_WORKERS=1 bin/rails test test/controllers/ai_assistants_controller_test.rb test/services/ai_assistant_tools_test.rb test/services/ai_assistant_queries_test.rb test/services/ai_assistant_daily_briefing_test.rb test/jobs/ai_assistant_job_test.rb`

Os testes cobrem autenticação, isolamento entre contas, matriz de setores/perfis, bloqueio por IDs e chamadas de funções não anunciadas, paginação, saldos e metas sobrepostas, resumo diário, ausência de dados/integrações, consultas sem escrita, privacidade das conversas, continuidade de funções, cancelamento e falhas do provedor. As chamadas externas são simuladas nos testes.
