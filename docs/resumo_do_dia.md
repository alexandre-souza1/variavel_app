# Resumo do dia nas notificações

Cada usuário pode ativar ou desativar **Resumo do dia** diretamente no menu do sino.
A opção começa **desativada**, inclusive nas contas que já existiam. Abrir o menu não
chama o Gemini. O envio usa todos os dias da semana, às 8h no fuso `Brasilia`.
Ao ativar depois das 8h, o primeiro envio fica para as 8h do dia seguinte.

O resumo reúne os mesmos dados da consulta `daily_briefing` do assistente: agenda
pessoal e módulos permitidos ao usuário. O Gemini apenas redige os dados consultados;
não recebe funções para criar registros nem acesso à conversa privada. O consumo é
registrado por usuário como **Resumo do dia** na administração de IA.

Quando gerado, o conteúdo completo fica salvo em `DailySummary`. A notificação
**Ler resumo** abre esse registro privado, sem outra chamada à IA. O push Android usa
o fluxo já existente, quando configurado e disponível para o dispositivo.

## Agendamento e recuperação

O scheduler do worker Sidekiq existente enfileira `DailySummaryDispatchJob` a cada
minuto. Não exige outro dyno nem addon de cron. Requer o worker ativo e a chave do
Gemini configurada. A geração começa a partir das 8h; o momento de conclusão depende
da fila e da resposta do provedor.

Cada usuário tem `daily_summary_enabled` e `daily_summary_next_run_at`. As reservas
de fila expiram em cinco minutos para permitir recuperação de jobs perdidos ou de
workers interrompidos. Bloqueios de linha, tokens por tentativa e o índice único de
usuário/data evitam notificações duplicadas, inclusive quando a notificação é apagada.
A criação da notificação, o resumo entregue e o próximo horário são gravados na mesma
transação. O Gemini é chamado fora da transação, sem manter bloqueado o cadastro.

Falhas deixam o resumo pendente e usam novas tentativas com espera crescente, até
uma hora, enquanto ainda for o mesmo dia. Os modelos alternativos seguem a configuração
existente. Desativação ou inativação da conta é conferida antes de gerar e antes de
entregar. Se o perfil/setor mudar durante a geração, a resposta é descartada e a
consulta é refeita com as permissões atuais. Não são enviados resumos atrasados de
dias anteriores: após indisponibilidade do worker, somente o dia atual é considerado.

O horário é um agendamento, não uma garantia de disponibilidade do Gemini, Redis,
worker ou push. Em falhas, `last_error`, `attempts` e `next_attempt_at` permitem
acompanhar as tentativas sem registrar respostas HTTP, credenciais ou prompts nos logs.

## Validação

`test/models/daily_summary_test.rb`, `test/jobs/daily_summary_jobs_test.rb`,
`test/services/daily_summary_generator_test.rb` e os testes dos controllers cobrem
o padrão desativado, horário de Brasília, permissões, cancelamento, recuperação,
falhas do Gemini, conteúdo privado e deduplicação. O teste de navegador
`test/browser/daily_summaries_test.cjs` verifica a preferência no sino e a leitura.
