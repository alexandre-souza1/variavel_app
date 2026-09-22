# Layout do pátio

`GET /patio` é público. Os atalhos de Consultas e AZ Consultas usam essa página; `?origem=az` mantém o retorno para a consulta do armazém.

O mapa em HTML/CSS reproduz as 40 vagas do PDF fornecido: primeira fileira em ordem 18–1, segunda fileira 19–35 com passagem entre 26 e 27, e extensão do armazém com as vagas 36–40. As características de cada vaga estão em `config/parking_layout.json`. A geometria é uma representação do layout de referência, não uma planta em escala.

## Placas e publicação

Somente registros ativos de `Plate` do tipo Caminhão ou Van ficam disponíveis. A configuração inicial aproveita as posições do PDF apenas quando a placa existe nesse cadastro ativo. Placas ausentes, inativas ou renomeadas não aparecem no mapa ou nas opções de edição. Veículos ativos sem posição ficam na lista de placas sem vaga do administrador.

`parking_layouts` guarda uma distribuição única no banco, com as 40 posições, usuário responsável, data e versão. A leitura não cria registros: a distribuição inicial é calculada até a primeira publicação pelo administrador. Alterações só são publicadas com “Salvar distribuição”. Isso funciona no Heroku sem depender do filesystem para persistir posições.

`PATCH /patio` exige `current_user.admin?` no servidor, além da proteção CSRF do Rails. O servidor rejeita posições incompletas, placas duplicadas, placas fora do cadastro ativo e versões desatualizadas. A atualização usa optimistic locking para evitar sobrescritas entre administradores.

## Edição

Apenas administradores recebem os controles de edição no HTML. No computador, Sortable é inicializado somente depois de “Editar posições”, com largura mínima de 901 px e dispositivo com ponteiro preciso/hover. Mover para uma vaga ocupada troca as duas placas. No celular não há Sortable nem alças visíveis; o administrador usa os seletores de placa e destino. A alternativa por seletores também atende navegação por teclado no computador.

O mapa público inclui busca por placa/vaga, zoom e visualização em lista. As posições representam a organização prevista, não ocupação física em tempo real.

## Deploy e verificação

Execute `bin/rails db:migrate` (o release do Heroku já executa migrations). A migration foi aplicada no banco local durante a implementação.

```sh
bin/rails test test/controllers/parking_layouts_controller_test.rb
bin/rails assets:precompile
npx --yes @herb-tools/linter@0.10.4 app/views/parking_layouts/show.html.erb app/views/parking_layouts/_space.html.erb
```
