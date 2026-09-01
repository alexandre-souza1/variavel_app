# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

## Disponibilidade da frota

O fechamento automático e a abertura da disponibilidade do dia seguinte são executados pela tarefa:

```sh
bin/rails fleet_availabilities:daily
```

Configure essa tarefa no scheduler do ambiente para rodar pelo menos a cada minuto (fuso de Brasília). Os horários de abertura e fechamento podem ser alterados no botão **Configurações** do índice de disponibilidades. O fechamento trava a disponibilidade do próximo dia para envio.

## Arquitetura de assets SCSS

O entrypoint principal é `app/assets/stylesheets/application.scss`. A ordem de importação foi deixada determinística para preservar a cascata do Bootstrap, carregar tokens compartilhados antes dos componentes e manter os overrides finais apenas em camadas específicas (tema escuro, calendário e utilitários).

- `custom/_index.scss` carrega variáveis, tokens e breakpoints antes dos componentes compartilhados.
- `components/_index.scss` e `pages/_index.scss` ficam após as bases globais para que regras de página tenham precedência explícita quando necessário.
- Ajustes de tema e utilitários sob `app/assets/stylesheets/custom/` permanecem no fim para evitar sobrescritas por regras gerais de layout.

* Deployment instructions

* ...
