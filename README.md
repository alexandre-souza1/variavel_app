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

* Deployment instructions

* ...
