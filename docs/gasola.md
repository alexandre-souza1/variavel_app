# Consumo dos motoristas — Gasola

A consulta de variável exibe “Meu consumo” para motoristas e motoristas de van, após selecionar mês e ano. A busca usa a matrícula exata (sem espaços nas extremidades), nunca o nome. Registros sem correspondência ficam armazenados, mas não são atribuídos a outra pessoa.

## Configuração e execução

Configure `GASOLA_API_TOKEN` no ambiente do servidor. O valor é enviado diretamente no cabeçalho Authorization; não adicionar Bearer. A integração usa exclusivamente a API de produção do Gasola. Nunca colocar a chave no navegador ou versioná-la.

```sh
bundle exec rails db:migrate
bundle exec rake gasola:sync
```

O `Procfile` inclui o processo `gasola: bundle exec rake gasola:work`. **É necessário habilitar uma instância desse processo na hospedagem**; adicionar a linha ao Procfile não ativa o processo por si só. Ele sincroniza ao iniciar e depois a cada hora. Em caso de falha mantém os dados anteriores e tenta novamente na hora seguinte. Não depende de Redis ou do worker Sidekiq.

Alternativa: executar `bundle exec rake gasola:sync` em um agendador externo a cada hora, sem habilitar o processo `gasola`. A trava PostgreSQL impede execuções simultâneas.

Por padrão, cada sincronização relê o período de fechamento atual e o anterior (21 a 20), até o instante da consulta. Intervalos acima de 30 dias são divididos em janelas contíguas. O ID do Gasola evita duplicação, inclusive nas fronteiras das janelas. Os registros existentes são atualizados; não são apagados quando deixam de vir na resposta. Correções de status recebidas pela API retiram o registro do cálculo quando ele deixa de estar concluído.

Para carregar ou revisar períodos antigos:

```sh
FROM=2026-07-21T00:00:00-03:00 TO=2026-08-21T00:00:00-03:00 bundle exec rake gasola:sync
```

A interface usa a data de aprovação `dataConclusao`, interpretada no fuso Brasília. O formato documentado não traz offset; confirmar esse fuso com o Gasola se houver divergência nas viradas do dia. Dados são salvos somente após todas as janelas e registros serem validados. Falhas HTTP e respostas inválidas não substituem o último resultado.

## Cálculos

- Apenas abastecimentos `CONCLUDED`, categoria `veículo`, dos combustíveis reconhecidos. ARLA e empilhadeiras ficam fora.
- Média = soma de `kmRodado` / soma de `totalLitros`, em registros com ambos positivos. Ausências, zeros e negativos são sinalizados e excluídos da média e meta.
- Meta do período = soma de (`metaKmPorLitro` × `totalLitros`) / soma de `totalLitros`, sobre os mesmos registros. Esta é a regra de ponderação do aplicativo, não uma afirmação sobre a fórmula do relatório consolidado do Gasola. Se faltar meta positiva em qualquer registro válido, não há comparação agregada.
- O resumo por placa aplica as mesmas regras. O card informa quando o período ainda não foi inteiramente sincronizado e quando a atualização do período aberto está atrasada.
- Consumo é informativo e não modifica cálculos ou snapshots da remuneração variável. A importação legada de CSV continua separada.

## Validação

```sh
bundle exec rails test test/services/gasola_test.rb test/services/gasola_client_test.rb test/controllers/consultas_controller_test.rb
```

Antes de liberar em produção, comparar os totais de alguns motoristas com o painel Gasola, principalmente a regra de ponderação da meta. A API foi validada com dados reais; essa comparação visual com o painel do fornecedor depende de acesso ao painel.

## Painel do time

`/fuel_consumptions` (também `/fuel_consumptions/index`) apresenta o painel autenticado do time. O padrão é o fechamento atual de 21 a 20; datas personalizadas são limitadas a 366 dias. Filtros por matrícula, placa e combustível se aplicam às médias, gráficos, tabelas e emissões. Os registros CSV permanecem em uma seção legada, fora desses indicadores.

A sincronização armazena `emissaoCo2`, `emissaoCo2Meta` e `impactoCo2` sem conversão. O painel mostra total e média aritmética de emissão por abastecimento com emissão não negativa, incluindo zero válido e excluindo campos ausentes. A cobertura informa quantos registros entraram na conta. A unidade não foi informada pela documentação: a interface identifica os valores como unidade da API, sem atribuir kg ou toneladas. Confirmar a unidade com o Gasola antes de usar em inventários ambientais. Após migrar, execute `bundle exec rake gasola:sync` para preencher as emissões do período atual e anterior; períodos antigos precisam de uma sincronização explícita.
