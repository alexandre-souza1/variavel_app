# Escala de folgas 5×2

Acesse **DU → Escala de folgas 5×2** ou **RH → Escala de folgas 5×2**, em `/escala-folgas`.

O piloto começa em 01/10/2026. O rodízio A–F segue continuamente por ciclos de seis semanas, usando 28/09/2026 como segunda-feira de referência do grupo A. Os domingos são DSR para todos. O grupo Fixo folga aos sábados e domingos.

## Preparação

```sh
bin/rails db:migrate
bin/rails time_off:setup
```

A composição inicial está em `config/time_off_pilot.yml`. A tarefa vincula somente cadastros ativos com correspondência única, normalizando maiúsculas, acentos e espaços. Duas variações de nome usam o código Promax da aba depara da planilha: Anderson Pereira / Anderson Pereira de Lara (187) e Alberto Ramon Frutos Gonzalez / Alberto Ramon Frutos (170). A tarefa não cria colaboradores nem altera os dados dos cadastros. Pode ser repetida sem recriar vínculos existentes.

“AJUDANTE 1” do grupo A e “AJUDANTE 2” do grupo B são vagas. Para preencher uma vaga, abra **Adicionar participante ou alterar grupo**, selecione o cadastro real, a vaga da composição inicial e o grupo correspondente.

### Produção (Heroku)

Inclua todos os arquivos novos do módulo no commit, incluindo as quatro migrações, serviços, views, controllers JavaScript e `config/time_off_pilot.yml`. Os arquivos CSV/XLSM usados como referência local não são necessários para o deploy.

O `Procfile` já executa `db:migrate` na fase de release, e os assets são compilados no build. Após o primeiro deploy do módulo, execute a composição inicial:

```sh
heroku run bundle exec rails time_off:setup --app NOME_DA_APP
```

Revise os participantes pendentes em **Configuração**, confirme o dimensionamento de outubro no banco de produção e os cargos/titulares de Van, Vespertina e AS. Dados cadastrados no banco local não são transferidos pelo deploy. A consulta da IA usa a configuração Gemini já existente no aplicativo.

## Uso

O módulo está dividido em cinco abas, cada uma com seu conteúdo:

- **Calendário:** blocos semanais do mês ou mês inteiro, com paginação dos participantes. A tabela mantém o visual original, a legenda dos grupos dentro do painel e a rolagem horizontal quando necessária. Todos os colaboradores da página aparecem sem rolagem vertical interna; os botões usam o tema de cores do aplicativo. Selecionar um dia abre a aba Escala do dia.
- **Escala do dia:** três colunas lado a lado no desktop: Em escala, De folga e Indisponíveis. Dentro de cada coluna, os cartões ocupam três posições por linha quando há espaço, duas em colunas menores e uma quando necessário. No celular, as colunas de situação ficam empilhadas.
- **Cobertura:** painel de carros dimensionados, com vagas de motorista e ajudantes e listas de disponíveis, folga e indisponíveis.
- **Extras:** total mensal e datas de trabalho nas folgas originais, por colaborador.
- **Histórico:** alterações da data selecionada, com responsável e motivo.

A data e os filtros são mantidos ao trocar de aba. Os filtros exibidos acompanham o conteúdo: mês no Calendário e em Extras; dia na Escala do dia, Cobertura e Histórico. O botão **Configuração** abre um painel lateral para férias, composição do piloto, vagas, alterações de grupo e continuação do rodízio. A legenda do calendário mostra os grupos e suas folgas originais.

- O calendário mostra colaborador por linha e dia por coluna. As cores identificam os grupos. `T` = em escala, `F` = folga, `D` = DSR, `I` = indisponível, `V` = férias. O ponto indica ajuste individual diferente do rodízio. Dias anteriores ao piloto ou fora da vigência ficam com traço.
- Os botões de período seguem o protótipo: **01–07**, **08–14**, **15–21**, **22–28**, **29–31** e **Mês inteiro**. O primeiro bloco é selecionado inicialmente; o último termina no último dia do mês (fevereiro, por exemplo, pode ter apenas quatro blocos). Um clique troca o período e preserva a página atual. A paginação mostra **12 colaboradores** por página, com **Anterior**, **1 / N** e **Próxima**, preservando função, grupo e período. As trocas atualizam somente o calendário e mantêm a posição da tela. Alterar os filtros reinicia a paginação. As setas do cabeçalho navegam entre meses. A legenda dos grupos e a contagem de extras continuam considerando o mês inteiro.
- Selecione um dia, função ou grupo. Arraste um colaborador entre Em escala, De folga e Indisponíveis. Ao soltar, informe o motivo e salve na confirmação. Cancelar não muda a escala.
- Convocar alguém de folga altera somente a data selecionada. A compensação deve ser registrada separadamente na data combinada. **Restaurar rodízio original** recupera a situação prevista para o dia, preservando o histórico.
- Mudanças de grupo têm uma data efetiva posterior ao início da vigência atual. Datas anteriores mantêm o grupo antigo; ajustes individuais futuros são preservados no novo vínculo.
- A configuração de continuação permite limitar a consulta a outubro ou manter o rodízio após o mês.

Administradores, supervisores e usuários de DU, RH ou Planejamento podem editar. Outros usuários autenticados podem consultar; mecânicos permanecem no fluxo próprio. Cada alteração diária registra responsável, situação anterior, situação nova, motivo e horário. Se outra pessoa já alterou o mesmo colaborador e dia, a edição retorna conflito e pede atualização da página.

Somente participantes ativos aparecem no Calendário, Escala do dia, Cobertura, Extras e nas seleções de Configuração. A inativação no cadastro de Motorista/Ajudante ou no RH retira a pessoa das listas e sugestões; uma posição salva com essa pessoa fica vaga ao consultar novamente. Tentativas de edição por páginas antigas são rejeitadas. Vínculos, férias, composições e alterações anteriores continuam armazenados, e o Histórico preserva os nomes dos colaboradores desligados.

## Extras e férias

Uma extra corresponde a um dia cujo rodízio original prevê folga e cuja situação atual é **Em escala**. A aba Extras mostra o total do mês e permite abrir cada data; o calendário e os cartões do dia também exibem o total por colaborador. Repetir o salvamento não duplica a contagem. Restaurar a folga, registrar indisponibilidade ou colocar a pessoa de férias retira esse dia do total. Datas futuras já convocadas também entram no relatório. Trocas de grupo mantêm a contagem unificada pela identidade do colaborador.

Em **Configuração → Férias**, selecione o colaborador, o início, o último dia de férias e o motivo. O período inclui as duas datas e os domingos. Durante as férias, a pessoa aparece em Indisponíveis com uma identificação própria, sem poder ser arrastada ou alocada nos carros. A situação de férias prevalece sobre ajustes anteriores e acompanha mudanças de grupo. As férias não alteram o rodízio nem apagam decisões diárias existentes.

O painel lateral lista os períodos ativos que alcançam o mês selecionado. É possível cancelar um período com motivo e registrar outro. O cancelamento preserva o registro e o histórico e faz a disponibilidade anterior voltar a valer. Registro e cancelamento são auditados na data inicial das férias. Sobreposições de férias e períodos sem vínculo válido na escala são rejeitados.

## Demanda, operações fixas e composição

A aba **Cobertura** usa `FleetDimensioning.for_date` para obter as quantidades de Rota padrão, Vespertina, AS e Van vigentes na data. Não usa o número de mapas nem inclui freteiros. Sem um dimensionamento vigente, a demanda aparece como não definida, com acesso ao cadastro da frota; nenhum número fixo substitui o cadastro.

De segunda a sexta, entram as quatro operações. No sábado entram somente as rotas padrão; Vespertina, AS e Van folgam. Domingo é DSR para todos. Com 18 rotas padrão e uma saída de cada operação fixa, são 21 saídas nos dias úteis e 18 no sábado.

Os titulares do piloto são André (motorista) e Alberto (ajudante) na Vespertina, e Keberson (motorista) no AS. A chave **Titular de operação fixa**, no cadastro do grupo, permite mudar essas definições com vigência e histórico. Exige grupo Fixo com folga no sábado. A tarefa `time_off:setup` também completa essas chaves nos vínculos iniciais já existentes, sem sobrescrever operações definidas pelo gestor ou vigências posteriores.

A Van usa o cargo **Motorista de van** vigente na data, obtido do histórico de cargos do colaborador. Ademar já possui esse cargo no cadastro; nenhum cargo é alterado pela configuração da escala. Outro motorista não pode ser colocado para dirigir a Van sem esse cargo vigente.

Vespertina prevê motorista e um ajudante; AS e Van preveem apenas motorista. Seus titulares já aparecem nos respectivos carros e não podem ocupar duas posições ao mesmo tempo.

O painel abre com uma **sugestão pela escala**: preserva as três duplas titulares de cada grupo informado, distribui os demais colaboradores em trabalho para cobrir as posições abertas e mantém o grupo de folga na lista lateral. Usa as placas padrão do dimensionamento quando cadastradas; posições sem placa continuam identificadas como Carro 1, Carro 2 etc. A sugestão não é gravada durante a consulta. Após salvar, os remanejamentos e vagas deixadas em branco são mantidos, sem redistribuir todas as equipes a cada abertura.

Arraste um nome para a vaga de motorista ou ajudante. Também é possível selecionar o nome e clicar ou tocar na vaga, inclusive pelo teclado e no celular. Substituir um nome devolve a pessoa anterior para Disponíveis. O botão de retirar do carro apenas desaloca; não registra folga ou ausência.

Arrastar para **De folga** ou **Indisponíveis** altera a situação daquele dia no rascunho. Tirar alguém de folga para colocar em um carro convoca a pessoa para trabalhar. **Salvar painel** pede um motivo e grava a composição e todas as mudanças de disponibilidade juntas, com histórico; uma validação ou conflito rejeita o conjunto inteiro. A compensação da folga continua sendo registrada na data combinada. **Desfazer rascunho** retorna ao estado inicial da tela, sem gravações.

Para cada carro da rota padrão, selecione **Sem ajudante**, **1 ajudante** ou **2 ajudantes**. Reduzir a quantidade devolve os nomes das vagas retiradas para Disponíveis. A composição de referência é um ajudante; saídas sem ajudante são permitidas por decisão do gestor. O painel mostra motoristas alocados e vagas de ajudante separadamente.

Motoristas podem ser colocados excepcionalmente nas vagas de ajudante. Mover a pessoa entre posições libera a anterior: cada colaborador ocupa uma única vaga. Ajudantes na direção, cargos incompatíveis, pessoas inativas e duplicidades são rejeitados. Indisponibilidades registradas depois de salvar deixam a posição vaga e mostram a pessoa na lista correspondente, preservando as outras equipes.

Os ajustes são exclusivos da data, exigem motivo e aparecem no Histórico. A revisão da composição e a assinatura do dimensionamento impedem que uma página desatualizada sobrescreva uma edição mais recente. Uma mudança posterior de dimensionamento ou uma ausência gera aviso para revisão. Trocas de grupo preservam as escolhas futuras pela identidade do colaborador.

## Relação com os mapas e futuras integrações

Os vínculos usam `Driver` e `Ajudante`, exibindo o código `promax` usado nos campos `matric_motorista`, `matric_ajudante` e `matric_ajudante_2` de `Mapa`. Esta etapa monta as equipes nas posições dimensionadas e apresenta suas placas padrão. A vinculação aos mapas, a geração da planilha de roteirização e a integração com os veículos efetivamente disponíveis em `FleetAvailability` ficam para a próxima etapa.

## Consulta pessoal em Mapas

Na consulta pessoal de Mapas, **Minhas folgas da semana** começa recolhido em uma faixa compacta, como **Meu consumo**, mostrando o próximo descanso no resumo. **Ver detalhes** expande a semana atual de segunda a domingo. **Minha escala do mês** expande um calendário apenas do colaborador, com seleção de mês independente do fechamento da variável de 21 a 20; ao selecionar outro mês, os painéis permanecem abertos para mostrar o resultado. Dias sem escala vigente aparecem como “Sem escala”; cadastros sem grupo e pessoas inativas recebem uma mensagem de ausência de escala.

A IA do chat público recebe a escala da pessoa identificada pela matrícula e nascimento, respeitando vínculos de RH e mudanças datadas de grupo/cargo. Pode responder “quando é minha próxima folga?” usando os ajustes e férias registrados. O próximo descanso inclui hoje, distingue Folga de DSR e consulta até 365 dias à frente; férias e indisponibilidades não são contadas como folga. O contexto não contém nomes de outras pessoas nem motivos de afastamentos.

## Validação

```sh
PARALLEL_WORKERS=1 bin/rails test test/services/time_off test/controllers/time_off_schedules_controller_test.rb
```

O teste de navegador usa somente o banco de testes. Prepare os cadastros e inicie um servidor de teste antes de executá-lo:

```sh
RAILS_ENV=test bin/rails runner test/browser/time_off_setup.rb
PIDFILE=tmp/pids/time_off_test.pid RAILS_ENV=test bin/rails server -p 4318 -P tmp/pids/time_off_test.pid
# Em outro terminal:
BASE_URL=http://127.0.0.1:4318 node test/browser/time_off_test.cjs
```
