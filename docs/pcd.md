# PCD

Acesse **DU → PCD**, em `/pcd`. O módulo é exclusivo para usuários do setor DU e administradores, com proteção também nos endpoints de importação, edição e PDF. O menu RH continua com a escala de folgas.

## Preparação

Execute `bin/rails db:migrate`. A migration `20261003100000_create_pcd_plans` cria o planejamento por data, as versões de importação e o histórico de execução. O Heroku usa a fase de release existente; o PCD não depende de Scheduler. Nenhuma tarefa altera dados de RH ou registros de `Mapa`.

## Fluxo do supervisor

1. Na Escala do dia, confirme quem está trabalhando, de folga e indisponível. Motoristas e ajudantes têm listas separadas.
2. No dia da saída, baixe o PW00943S e abra o PCD dessa data. **Carregar CSV** gera uma prévia com todas as rotas roteirizadas, incluindo freteiros. Confere a Data Entrega e preserva mapa, cidades, regiões e dados de carga. Linhas não roteirizadas são ignoradas.
3. Confira placas, operação, sala, horário e equipe. Arraste nomes disponíveis ou selecione um nome e toque na vaga. Ajudante 2 aparece ao escolher **2 ajudantes**; escolher **Sem ajudante** libera as vagas. Motoristas podem atuar excepcionalmente como ajudantes, e a Van exige o cargo vigente Motorista de van. O motorista informado no CSV é uma referência: a importação não convoca alguém de folga.
4. Em freteiros, o motorista externo é preenchido pelo cadastro quando há correspondência única pelo código. Também é possível informar nomes de motorista e ajudantes externos sem criar cadastros no RH.
5. Desmarque **Saída prevista** para cancelar uma saída: os colaboradores voltam para Disponíveis, sem registrar folga. Posições especiais sem mapa recebem aviso de conferência. A quantidade dimensionada não impõe limite à importação do PCD; a demanda da escala usa as saídas próprias salvas.
6. **Salvar PCD** pede motivo e grava roteirização, importação e histórico juntos. Uma validação ou conflito rejeita toda a gravação. **Desfazer rascunho** descarta também a importação ainda não salva.

O PCD funciona mesmo sem piloto de folgas configurado. Colaboradores ativos fora do piloto aparecem identificados como “sem escala no piloto”; podem ser alocados, mas não entram na contagem de disponibilidade dos participantes do piloto. Cadastros inativos e cargos incompatíveis ficam fora das sugestões. Para convocar alguém de folga ou corrigir uma ausência/férias, use a Escala do dia e recarregue o PCD.

## Salas e horários

O padrão segue a aba **PCD SALAS** da planilha de referência, com ajustes livres pelo supervisor:

| Sala | Horário inicial |
| --- | --- |
| Sala 01 · Rota | 07:00 |
| Sala 02 · Rota | 08:00 |
| Sala 03 · ASCD | 08:00 |
| Sala 04 · Vespertina | 12:00 |
| SPOT · Freteiros | 06:00 |

As salas são sugestões: freteiros vão para SPOT, AS para ASCD e Vespertina para a sala correspondente. Nas rotas padrão, cidades que começam por Foz sugerem Sala 02; as demais sugerem Sala 01. O supervisor confere e altera a sugestão. Operações próprias especiais podem ser reconhecidas pela placa padrão do dimensionamento ou pelo titular/cargo vigente; a classificação “Noturno” isoladamente não define Vespertina.

## Reimportação e auditoria

A aba **Importações** mostra arquivo, responsável, horário, saídas próprias, freteiros, mapas, cidades e regiões de cada versão salva. A aba **Histórico** registra motivo, alterações de placa, sala, horário, composição, equipe, observações, cancelamentos e impressões. Cada execução guarda o estado anterior e posterior.

Reimportar o mesmo conjunto de mapas atualiza os dados do relatório e preserva substituições de placa e ajustes de equipe, operação, sala, horário e saída cancelada. Os mapas não duplicam: vários mapas da mesma placa, motorista e operação ficam na mesma saída. Rotas importadas que sumiram da nova versão saem do planejamento atual, mantendo a versão anterior no histórico; posições dimensionadas sem mapa ficam pendentes ou sem saída. Arquivos de outra data, mapas conflitantes, placas repetidas entre saídas e alocações duplicadas são rejeitados. Páginas desatualizadas não sobrescrevem edições posteriores.

## PDF

Após salvar, **Imprimir PCD SALAS** abre um PDF A4 paisagem com as saídas salvas, agrupadas por sala e horário. Inclui data, placa, mapa, operação, códigos/nomes da equipe, entregas, cidades, regiões, KM, tempo, caixas, ocupação e peso. Cada grupo começa em uma página; a tabela repete o cabeçalho quando precisar continuar. Saídas canceladas ficam fora da impressão. Operações previstas sem mapa ou equipe mostram a pendência, e observações aparecem abaixo da tabela. A emissão também fica no Histórico. Os nomes e códigos dos dois ajudantes ficam juntos na coluna Ajudantes para facilitar a impressão.

## Validação

```sh
PARALLEL_WORKERS=1 bin/rails test test/services/pcd test/controllers/pcds_controller_test.rb test/services/time_off test/controllers/time_off_daily_routes_test.rb test/controllers/time_off_schedules_controller_test.rb
RAILS_ENV=test bin/rails runner test/browser/time_off_setup.rb
PIDFILE=tmp/pids/time_off_test.pid RAILS_ENV=test bin/rails server -p 4318 -P tmp/pids/time_off_test.pid
# Em outro terminal, sequencialmente:
node test/browser/time_off_test.cjs
RAILS_ENV=test bin/rails runner test/browser/time_off_setup.rb
node test/browser/time_off_routing_test.cjs
```

Não execute a preparação do navegador e os testes Rails simultaneamente: eles compartilham o banco de testes. O XLSM é referência visual; nenhuma macro é executada.
