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

Inclua todos os arquivos novos do módulo no commit, incluindo as migrações, serviços, views, controllers JavaScript e `config/time_off_pilot.yml`. Os arquivos CSV/XLSM usados como referência local não são necessários para o deploy.

O `Procfile` já executa `db:migrate` na fase de release, e os assets são compilados no build. Após o primeiro deploy do módulo, execute a composição inicial:

```sh
heroku run bundle exec rails time_off:setup --app NOME_DA_APP
```

Revise os participantes pendentes em **Configuração**, confirme o dimensionamento de outubro no banco de produção e os cargos/titulares de Van, Vespertina e AS. Dados cadastrados no banco local não são transferidos pelo deploy. A consulta da IA usa a configuração Gemini já existente no aplicativo.

## Uso

O módulo está dividido em quatro abas, cada uma com seu conteúdo:

- **Calendário:** blocos semanais do mês ou mês inteiro, com paginação dos participantes. A tabela mantém o visual original, a legenda dos grupos dentro do painel e a rolagem horizontal quando necessária. Todos os colaboradores da página aparecem sem rolagem vertical interna; os botões usam o tema de cores do aplicativo. Selecionar um dia abre a aba Escala do dia.
- **Escala do dia:** Em escala, De folga e Indisponíveis ficam lado a lado no desktop. Em escala possui duas listas: Motoristas e Ajudantes. Os nomes são compactos e não definem equipes ou placas. Arrastar entre situações pede motivo e salva somente a disponibilidade daquele colaborador. A demanda informa as saídas próprias e as faltas de pessoas: usa as saídas e composições salvas no PCD da data ou o dimensionamento como referência quando ainda não existe PCD. Freteiros ficam fora da necessidade do piloto. Os filtros não alteram os totais de demanda. Sem dimensionamento vigente, a disponibilidade continua acessível e a demanda não é estimada.
- **Extras:** total mensal e datas de trabalho nas folgas originais, por colaborador.
- **Histórico:** alterações da data selecionada, com responsável e motivo.

A data e os filtros são mantidos ao trocar de aba. Calendário e Extras oferecem o filtro por mês. Na Escala do dia e Histórico, as setas ao lado da data no cabeçalho permitem voltar ou avançar um dia. As setas preservam função, grupo e contexto do calendário e atravessam meses e anos; não há seletor de data nessas abas. O botão **Configuração** abre um painel lateral para férias, composição do piloto, vagas, alterações de grupo e continuação do rodízio. A legenda do calendário mostra os grupos e suas folgas originais.

- O calendário mostra colaborador por linha e dia por coluna. As cores identificam os grupos. `T` = em escala, `F` = folga, `D` = DSR, `I` = indisponível, `V` = férias. O ponto indica ajuste individual diferente do rodízio. Dias anteriores ao piloto ou fora da vigência ficam com traço.
- Os botões de período seguem o protótipo: **01–07**, **08–14**, **15–21**, **22–28**, **29–31** e **Mês inteiro**. O primeiro bloco é selecionado inicialmente; o último termina no último dia do mês (fevereiro, por exemplo, pode ter apenas quatro blocos). Um clique troca o período e preserva a página atual. A paginação mostra **12 colaboradores** por página, com **Anterior**, **1 / N** e **Próxima**, preservando função, grupo e período. As trocas atualizam somente o calendário e mantêm a posição da tela. Alterar os filtros reinicia a paginação. As setas do cabeçalho navegam entre meses. A legenda dos grupos e a contagem de extras continuam considerando o mês inteiro.
- Selecione um dia, função ou grupo. Arraste um nome para Em escala, De folga ou Indisponíveis e informe o motivo. Um motorista só entra na lista de motoristas; um ajudante entra na lista de ajudantes. Quem está de férias não pode ser movido. As composições, vagas de ajudantes e placas são responsabilidade do módulo **DU → PCD**.
- Convocar alguém de folga altera somente a data selecionada. A compensação deve ser registrada separadamente na data combinada. **Restaurar rodízio original** recupera a situação prevista para o dia, preservando o histórico.
- Mudanças de grupo têm uma data efetiva posterior ao início da vigência atual. Datas anteriores mantêm o grupo antigo; ajustes individuais futuros são preservados no novo vínculo.
- A configuração de continuação permite limitar a consulta a outubro ou manter o rodízio após o mês.

Administradores, supervisores e usuários de DU, RH ou Planejamento podem editar. Outros usuários autenticados podem consultar; mecânicos permanecem no fluxo próprio. Cada alteração diária registra responsável, situação anterior, situação nova, motivo e horário. Se outra pessoa já alterou o mesmo colaborador e dia, a edição retorna conflito e pede atualização da página.

Somente participantes ativos aparecem no Calendário, Escala do dia, Extras e nas seleções de Configuração. A inativação no cadastro de Motorista/Ajudante ou no RH retira a pessoa das listas e sugestões; uma posição salva com essa pessoa fica vaga ao consultar novamente. Tentativas de edição por páginas antigas são rejeitadas. Vínculos, férias, composições e alterações anteriores continuam armazenados, e o Histórico preserva os nomes dos colaboradores desligados.

## Extras e férias

Uma extra corresponde a um dia cujo rodízio original prevê folga e cuja situação atual é **Em escala**. A aba Extras mostra o total do mês e permite abrir cada data; o calendário e os cartões do dia também exibem o total por colaborador. Repetir o salvamento não duplica a contagem. Restaurar a folga, registrar indisponibilidade ou colocar a pessoa de férias retira esse dia do total. Datas futuras já convocadas também entram no relatório. Trocas de grupo mantêm a contagem unificada pela identidade do colaborador.

Em **Configuração → Férias**, selecione o colaborador, o início, o último dia de férias e o motivo. O período inclui as duas datas e os domingos. Durante as férias, a pessoa aparece em Indisponíveis com uma identificação própria, sem poder ser arrastada ou alocada nos carros. A situação de férias prevalece sobre ajustes anteriores e acompanha mudanças de grupo. As férias não alteram o rodízio nem apagam decisões diárias existentes.

O painel lateral lista os períodos ativos que alcançam o mês selecionado. É possível cancelar um período com motivo e registrar outro. O cancelamento preserva o registro e o histórico e faz a disponibilidade anterior voltar a valer. Registro e cancelamento são auditados na data inicial das férias. Sobreposições de férias e períodos sem vínculo válido na escala são rejeitados.

## Demanda e conexão com o PCD

O dimensionamento é a capacidade prevista, não a obrigação de usar todos os carros. A Escala do dia usa `FleetDimensioning.for_date`: Rota padrão, Vespertina, AS e Van de segunda a sexta; somente Rota padrão no sábado; domingo é DSR. Com 18 rotas padrão e uma de cada especial, são 21 posições dimensionadas nos dias úteis e 18 no sábado. As saídas efetivas podem ser menores.

Quando há um PCD salvo na data, a demanda considera somente as saídas próprias ativas e suas quantidades de ajudantes. Posições sem saída e freteiros não geram necessidade do piloto. O número de pessoas em escala vem da disponibilidade do dia, independentemente da alocação em equipes. Motoristas usados como ajudantes no PCD são contabilizados nessa função para calcular as faltas. Alterações de disponibilidade aparecem no PCD ao recarregar; quem ficou indisponível, de férias ou inativo deixa a vaga pendente para revisão.

Os titulares iniciais continuam configurados no piloto: André e Alberto na Vespertina, Keberson no AS; Ademar é validado pelo cargo Motorista de van no RH. Essas definições ajudam a sugestão inicial do PCD e a classificação do CSV, mas a Escala do dia não monta equipes.

**Cobertura** foi retirada das abas. Links antigos com `tab=coverage` redirecionam para `/pcd` na mesma data. Os antigos endpoints de composição e importação retornam 410 para impedir gravações por páginas desatualizadas. As composições e o histórico anteriores permanecem no banco, servindo de sugestão ao abrir um PCD ainda não salvo. Os detalhes completos do CSV devem ser carregados no PCD para preencher cidades e regiões.

Veja [PCD e impressão por salas](pcd.md) para importação, composição e histórico.

## Consulta pessoal em Mapas

Na consulta pessoal de Mapas, **Minhas folgas da semana** começa recolhido em uma faixa compacta, como **Meu consumo**, mostrando o próximo descanso no resumo. **Ver detalhes** expande a semana atual de segunda a domingo. **Minha escala do mês** expande um calendário apenas do colaborador, com seleção de mês independente do fechamento da variável de 21 a 20; ao selecionar outro mês, os painéis permanecem abertos para mostrar o resultado. Dias sem escala vigente aparecem como “Sem escala”; cadastros sem grupo e pessoas inativas recebem uma mensagem de ausência de escala.

A IA do chat público recebe a escala da pessoa identificada pela matrícula e nascimento, respeitando vínculos de RH e mudanças datadas de grupo/cargo. Pode responder “quando é minha próxima folga?” usando os ajustes e férias registrados. O próximo descanso inclui hoje, distingue Folga de DSR e consulta até 365 dias à frente; férias e indisponibilidades não são contadas como folga. O contexto não contém nomes de outras pessoas nem motivos de afastamentos.

## Validação

```sh
PARALLEL_WORKERS=1 bin/rails test test/services/time_off test/controllers/time_off_schedules_controller_test.rb test/controllers/time_off_daily_routes_test.rb
```

O teste de navegador usa somente o banco de testes. Prepare os cadastros e inicie um servidor de teste antes de executá-lo:

```sh
RAILS_ENV=test bin/rails runner test/browser/time_off_setup.rb
PIDFILE=tmp/pids/time_off_test.pid RAILS_ENV=test bin/rails server -p 4318 -P tmp/pids/time_off_test.pid
# Em outro terminal:
BASE_URL=http://127.0.0.1:4318 node test/browser/time_off_test.cjs
# Reprepare os dados antes de testar a importação:
RAILS_ENV=test bin/rails runner test/browser/time_off_setup.rb
BASE_URL=http://127.0.0.1:4318 node test/browser/time_off_routing_test.cjs
```

Execute a preparação, os testes de navegador e os testes Rails sequencialmente: eles compartilham o banco de testes.
