# Consumo de IA por modelo

Em **Admin → Configurações de IA**, o painel ocupa a largura disponível e organiza o acompanhamento em quatro abas:

- **Visão geral:** totais, evolução por dia/recurso e comparação entre modelos. É possível comparar chamadas aceitas ou tokens de entrada e filtrar por 7, 30 ou 90 dias, modelo e recurso.
- **Modelos e cotas:** disponibilidade estimada por modelo na janela diária do Google e nos últimos 60 segundos.
- **Uso por usuário:** contas e colaboradores com chamadas aceitas, comparação de uso, distribuição por recurso, tentativas, tokens, falhas, tempo médio e último uso. A tabela tem busca por nome e paginação de 20 registros.
- **Configurações:** modelo prioritário, tempo de gravação e limites de cada modelo.

As abas utilizam navegação do próprio aplicativo e mantêm os filtros dos relatórios. Os gráficos são interativos e acompanham o tema claro/escuro.

## Limites informados para este projeto

A migração de 15/10/2026 configura os valores enviados pelo administrador, usando os números depois da barra no AI Studio. Eles continuam editáveis na aba Configurações. Os contadores da captura não são importados como chamadas locais.

| Modelo | RPM | TPM de entrada | RPD |
| --- | ---: | ---: | ---: |
| Gemini 3.6 Flash | 5 | 250.000 | 20 |
| Gemini 3.1 Flash-Lite | 15 | 250.000 | 500 |
| Gemini 3.5 Flash-Lite | 15 | 250.000 | 500 |
| Gemini 2.5 Flash-Lite | 10 | 250.000 | 20 |

Os demais modelos listados no AI Studio não são adicionados à seleção do app por esta alteração.

## Configurar

1. Execute `bin/rails db:migrate` e reinicie o servidor e os workers.
2. Abra o link **Consultar limites no Google AI Studio** e selecione o projeto da chave configurada no app.
3. Copie os valores de RPM (requisições/minuto), TPM (tokens de entrada/minuto) e RPD (requisições/dia) para cada modelo.
4. Salve as configurações. Deixe campos desconhecidos em branco; zero indica ausência de cota.
5. Use **Atualizar dados** para buscar os dados registrados mais recentes. Abrir a página consulta o banco do app, sem gerar chamadas ao Gemini.

Os limites variam por projeto, modelo e nível da conta. Confira os valores quando houver mudanças no AI Studio. As cotas diárias do Gemini renovam à meia-noite do Pacífico; o painel converte os horários para Brasília, considerando as mudanças de horário de verão na origem. [Documentação de cotas do Gemini](https://ai.google.dev/gemini-api/docs/rate-limits).

## O que entra na contagem

- Assistente pessoal, chat público de variável e geração de atas.
- Cada requisição HTTP individual, incluindo rodadas de ferramentas, novas tentativas e modelos reserva.
- Chamadas aceitas, falhas, respostas 429 e tokens de entrada/saída informados pelo provedor.
- Os últimos 60 segundos para cotas por minuto e o dia do Google para a cota diária.

O restante estimado corresponde ao limite cadastrado menos as chamadas aceitas ou os tokens de entrada registrados, com mínimo zero. Chamadas recusadas e falhas ficam separadas. Se uma chamada aceita não informar tokens, o saldo de tokens daquela janela fica como **Dados parciais**. Um saldo desconhecido nunca é apresentado como zero.

Os registros começam com a ativação deste recurso e são separados pela chave da integração. A data de início aparece no painel. Uso anterior não pode ser reconstruído; trocar a chave inicia outra contagem mesmo que o projeto permaneça o mesmo. Como apenas este app usa o projeto, os dados passam a cobrir as chamadas dele a partir da ativação. O primeiro período pode estar incompleto.

Falhas sem consumo informado, outras restrições do provedor e alterações nos limites podem produzir diferenças em relação ao Google. O status informa o resultado da última chamada e sua data; ele não é uma verificação em tempo real nem uma garantia de disponibilidade. Se o Google informar quando tentar novamente após um 429, o painel exibe o horário sugerido.

## Estatísticas por usuário e privacidade

As novas chamadas guardam somente a referência à conta autenticada, além dos metadados de consumo. O assistente usa o dono da conversa. O processamento de atas usa a conta que solicitou a geração ou a nova tentativa; jobs antigos, sem esse argumento, usam o criador da ata. O chat de variável associa a chamada ao cadastro do colaborador validado por matrícula e data de nascimento, mesmo sem login. Essa identidade tem prioridade sobre uma eventual conta logada no mesmo navegador, evitando atribuir o consumo ao administrador. Cadastros vinculados ao RH usam o colaborador central; cadastros operacionais legados também são reconhecidos. O nome aparece na tabela, nos gráficos e na busca. O indicador de usuários ativos conta contas do sistema e cadastros de colaboradores distintos, sem tentar deduzir vínculos entre eles.

Chamadas anteriores à atualização não recebem uma identidade por inferência. Elas aparecem junto de outras chamadas sem conta na linha **Sem usuário associado**. A data de início da identificação aparece na aba Uso por usuário. A data de início da identificação dos colaboradores também é exibida; essa identificação não é retroativa. Remover uma conta preserva os contadores e remove sua associação. Se um cadastro de colaborador for removido, seus contadores permanecem identificados apenas pelo código interno como cadastro indisponível, sem guardar uma cópia do nome.

O relatório consulta `ai_api_requests` e somente IDs e nomes dos cadastros de contas e colaboradores. O consumo guarda apenas a referência ao cadastro, sem copiar matrícula, nascimento ou CPF. O relatório não consulta `ai_messages`, conversas, perguntas, respostas, áudios, matrícula, nascimento ou CPF. A tela não contém links para conversas de outras contas. Todos os relatórios e filtros permanecem restritos a administradores.

## Implementação e validação

`GeminiRequest.track` registra os metadados em `ai_api_requests`; não persiste chave, prompt, áudio ou resposta. A chave é identificada por um hash SHA-256. Uma falha no registro de uso não interrompe a operação nem altera as tentativas do Gemini. As cotas configuradas servem ao acompanhamento; não alteram o modelo prioritário ou o comportamento de reserva.

O painel e a edição dos limites usam a autorização de administrador já existente. Não são necessárias credenciais adicionais do Google Cloud.

```sh
PARALLEL_WORKERS=1 bin/rails test test/services/gemini_request_test.rb test/services/gemini_usage_dashboard_test.rb test/services/gemini_usage_report_test.rb test/controllers/admin/ai_settings_controller_test.rb test/jobs/meeting_minute_generation_job_test.rb
```
