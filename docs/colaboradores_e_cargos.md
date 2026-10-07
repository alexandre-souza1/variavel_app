# Colaboradores DU e AZ

O cadastro comum fica em **RH → Colaboradores** e nos menus DU/AZ. RH, supervisão e administração gerenciam pessoas; usuários DU e AZ consultam seu setor. Segurança e planejamento podem consultar os dois setores. Os endereços antigos de motoristas, ajudantes e operadores encaminham para esse cadastro.

Cada pessoa tem uma matrícula, dados pessoais e um histórico de vínculos. O vínculo define **setor, cargo, identificação operacional e período**:

| Setor | Cargo | Dados do vínculo | Recursos |
| --- | --- | --- | --- |
| DU | Motorista, motorista de van ou ajudante | Promax e data efetiva | Variável DU, escala 5×2 e PCD conforme função/disponibilidade |
| AZ | Operador ou ajudante | Turno A/B/C e data efetiva | Variável e dashboard AZ |

“Ajudante” é o cargo nos dois setores. O setor distingue suas regras; `az_ajudante` permanece apenas na compatibilidade com os registros antigos.

## Cadastro e movimentações

Cadastre a pessoa com o primeiro vínculo e sua data real. O motivo “Cadastro inicial” é registrado automaticamente, sem campo de justificativa na criação. Na ficha, use **Alterar setor, cargo ou turno** e informe o motivo da movimentação. A vigência anterior termina na véspera da nova. A DU mantém sua progressão ajudante → van/motorista → motorista; transferências entre setores e mudanças de turno AZ ficam no mesmo histórico. Para manter o cargo DU e mudar o Promax, use **Alterar somente o código Promax**.

**Editar dados** atualiza nome, matrícula, CPF e nascimento nos módulos vinculados, com motivo e responsável. Nomes e matrículas anteriores ficam como referências para importações históricas. Fontes ambíguas exigem revisão: o sistema não escolhe uma pessoa arbitrariamente nem associa consumo privado a um alias compartilhado.

**Inativar** encerra a possibilidade de atuar ou se identificar como pessoa ativa em todos os cadastros vinculados. Os registros operacionais, IDs, fechamentos e auditorias permanecem. **Reativar** restaura a situação do cadastro. A permissão para registrar autonomia aparece na edição quando há vínculo vigente de motorista DU ou operador AZ; um cargo antigo não concede essa permissão ao cargo atual.

## Recursos específicos

Escala 5×2 e PCD usam o vínculo DU na data da operação. Cadastro DU pelo RH já fica disponível nos seletores, mas a inscrição em um grupo e a disponibilidade continuam necessárias. Uma transferência agendada só altera a elegibilidade a partir de sua data. Referências antigas dos planos e das inscrições continuam sendo lidas.

O consumo pessoal é exclusivo dos períodos de motorista/van DU. A consulta mantém os abastecimentos associados às matrículas anteriores, respeita as datas do cargo e evita aliases pertencentes a mais de uma identidade. Ajudantes e vínculos AZ não recebem esse recurso para seu período exclusivo.

A consulta comum identifica setor/cargo/turno pela matrícula. O portal do chat usa matrícula e nascimento, sem exigir escolha entre tabelas de cadastro. Uma pessoa com histórico DU e AZ pode consultar as variáveis de cada setor separadamente.

## Variável e fechamentos

**DU: 21 do mês anterior a 20 do mês selecionado.** Cargo e Promax são avaliados na data de cada mapa, inclusive em importações atrasadas. Tarifas seguem suas vigências.

- O bônus exige pelo menos 15 mapas e devolução de até 3%, separadamente por cargo no fechamento. Mapas de van e motorista não são somados para atingir o mínimo.
- Van recebe bônus. Recarga de van paga caixas/entregas como mapa normal, entra nos volumes/devolução e não recebe tarifa de recarga; a marcação original permanece.
- Fator 2 divide caixas/entregas por dois. A regra de fator 0 com pelo menos dois PDVs permanece exclusiva de motorista.
- A tarifa do bônus é a vigente na última data de mapa daquele cargo no fechamento.

**AZ: 19 do mês anterior a 18 do mês selecionado.** Consulta, dashboard e chat compartilham `AzVariableReport`. Cargo e turno seguem a data de cada operação. WMS usa segundos, mínimo de 10 segundos e inclui a noite do último dia. Ajudantes A/B/C mantêm a EFC compartilhada, suprimento do turno A e remonte do turno B, com as exclusões de domingo já existentes.

Os fechamentos registrados são snapshots de fontes, vigências, tarifas, componentes e totais. DU e AZ têm revisões independentes. Corrigir o histórico ou alterar uma regra não sobrescreve um fechamento registrado: a consulta, o dashboard mensal e o chat usam a última revisão salva para o setor. Detalhes das fontes AZ também usam as tarifas registradas. Recortes parciais são prévias, sem ratear automaticamente o fechamento. Registrar fechamento não representa pagamento ou envio à folha.

Os endpoints de registro/revisão da ficha aceitam `employee_sector` (`du` ou `az`); os endereços existentes permanecem. Um fechamento AZ com turno desconhecido é recusado até a revisão do vínculo. Uma revisão recalcula o período com o histórico atual e conserva a versão anterior.

No dashboard DU, o carrossel tem páginas de produtividade, devolução (consolidado, colaboradores e evolução diária) e média histórica de variável, com três cards e o mesmo acabamento em cada página. O ranking de devolução mostra os nomes e permite alternar entre motoristas e ajudantes; o hover conserva o nome completo. Os carrosséis têm transições suaves, desativadas quando o sistema prefere movimento reduzido. As bolinhas dos gráficos de motoristas e ajudantes alternam entre as dez maiores e as dez menores remunerações, ordenadas por valor. As tabelas continuam ordenadas por quantidade de mapas.

A média de variável é uma referência **mensal histórica do grupo**, calculada com os 12 ciclos anteriores ao selecionado. Soma-se a variável por pessoa/mês e divide-se pela quantidade desses registros, usando apenas a última revisão de cada fechamento DU. Motorista e van da mesma pessoa são somados antes de contar uma observação; ajudante tem uma referência independente. Valores zerados com mapas entram, meses ausentes não são tratados como zero e a cobertura de meses/registros é exibida. Não é a média das médias mensais nem o total anual dividido pelo quadro atual. A consulta traz somente os grupos dos snapshots, sem carregar os mapas ou recalcular tarifas, e usa o índice `index_variable_closings_history`.

Os valores do período são comparados à referência histórica em centavos: acima, abaixo, na média ou sem histórico. Gráficos exibem até dez maiores diferenças por faixa, com nome completo no hover; a comparação completa lista todos os colaboradores. Homônimos permanecem distintos por matrícula. Períodos parciais são identificados porque são comparados com uma referência mensal completa.

O botão **Relatório gerencial** exporta um PDF do filtro atual (inclusive quinzenas), com 14 gráficos: Top/Bottom por função, mapas diários, devolução geral/por função/diária, média histórica e diferenças acima/abaixo por função. Traz todas as remunerações por cargo, base/bônus/origem e a comparação histórica completa. Alertas objetivos cobrem devolução superior a 3%, histórico incompleto, PDVs inválidos, problemas de vínculo/identificação, variável zerada e período parcial. O limite de devolução não determina sozinho a elegibilidade do bônus; ficar abaixo da referência mensal não determina pior desempenho. O PDF usa Prawn e gráficos vetoriais, sem dependência de navegador ou chamada de IA; fechamentos são apenas lidos. Gemini pode ser acrescentado para redigir uma análise complementar, mantendo esses números e regras como fonte.

A seção de devolução é um indicador operacional dos mapas do período selecionado: calcula `soma(PDVs previstos − entregues) / soma(PDVs previstos)`, contando cada mapa uma vez, e mostra até dez pessoas por função com devolução positiva, em ordem de percentual. Cada pessoa acumula os PDVs dos mapas em que participou, com reconhecimento pelo vínculo vigente e agrupamento da mesma identidade após mudanças de Promax. Os dois campos de ajudantes são considerados, sem duplicar uma pessoa no mesmo mapa. Homônimos recebem a matrícula no rótulo para conservar barras distintas. Recargas são excluídas, exceto as de van, conforme o cargo ou a correção do mapa; PDVs ausentes/inconsistentes ficam fora com a quantidade indicada. A evolução diária aplica a mesma ponderação, separadamente por data. Esse consolidado das fontes atuais não sobrescreve os percentuais dos fechamentos salvos.

## Cadastros antigos e importações

Na gestão de colaboradores, usuários do setor DU consultam apenas DU e usuários do Armazém apenas AZ, inclusive supervisores/administradores desses setores. A restrição vale no servidor, nas fichas, nas listas arquivadas e nos endereços antigos compartilhados. RH e os demais perfis autorizados mantêm a visão dos dois setores. O acesso usa o último vínculo iniciado, preservando o setor atual até a data efetiva de uma transferência futura; fichas restritas exibem apenas históricos e fechamentos do setor permitido. Links de retorno, edição e salvamento conservam os filtros conhecidos, sem aceitar um endereço de retorno arbitrário.

A coluna **Grupo** lê a vigência atual de `TimeOffMembership`; não há um segundo cadastro de grupos. O lápis abre a edição em um modal, mantendo a altura da linha; as pendências da escala usam o mesmo modal. Cancelar ou fechar descarta os campos ainda não salvos. Colaboradores DU sem grupo aparecem com o campo vazio e podem receber uma definição pela lista ou pelo aviso da escala. AZ não recebe grupos 5×2. Cada alteração informa a data efetiva, conserva vigências anteriores e registra auditoria pelo mesmo serviço da escala. Grupo Fixo mantém a folga/operação já cadastradas no formulário de edição. O aviso de pendências considera toda a equipe DU ativa na data consultada, sem esconder pessoas pelos filtros de grupo/função; cadastros operacionais ainda sem identidade central também aparecem uma vez.

As tabelas `drivers`, `ajudantes`, `operators` e `az_ajudantes` continuam como adaptadores para associações históricas de mapas, WMS, autonomias e outros módulos. `Employees::Registry` centraliza sua sincronização. Sua remoção exige outra migração dos consumidores históricos.

No CSV de cadastro, informe `inicio_cargo` como `AAAA-MM-DD`. Motoristas aceitam `cargo` igual a `motorista` ou `van`; AZ exige turno A/B/C. Os arquivos são transacionais: um erro reverte o cadastro daquele arquivo. Atualizações de código/turno em cadastros vinculados devem ser registradas como movimentações no RH.

Homônimos não são fundidos. O vínculo manual abre uma conferência dos cadastros e exige CPF coincidente, data e motivo. Ao incorporar um cadastro legado, seus IDs e fontes são preservados. Conflitos de fechamento DU seguem a consolidação já existente. Dois fechamentos AZ do mesmo período permanecem como referências para conferência, sem somar fontes potencialmente duplicadas; a auditoria do vínculo registra a necessidade de revisão.

## Implantação e conferência dos dados

Execute `bin/rails db:migrate` no ambiente de destino e publique os assets com o fluxo normal da aplicação. As migrações de 07/10/2026:

1. Acrescentam setor/turno ao histórico e tornam Promax específico da DU, com constraints no banco.
2. Vinculam operadores/ajudantes AZ ao cadastro comum, preservando seus IDs e os relacionamentos existentes.
3. Convertem matrícula AZ para texto; zeros já perdidos pelo armazenamento anterior como inteiro não podem ser recuperados automaticamente.
4. Acrescentam referências de pessoa à escala e às fontes AZ/WMS, histórico de nomes/matrículas e setor nos fechamentos.
5. Provisionam os adaptadores que faltavam em pessoas já cadastradas diretamente no RH, sem substituir IDs existentes nem inscrever pessoas automaticamente na escala.

Datas de início desconhecidas permanecem legadas. O turno anterior de um operador não pode ser reconstruído sem uma fonte histórica; mudanças futuras passam a ter vigência. Fechamentos AZ anteriores à implantação não são inventados. Migrações anteriores da DU mantêm suas referências legadas de tarifas e fechamentos, que não são comprovantes de pagamento.

Rode `bin/rails employees:audit` para obter IDs de vigências sem data/turno, matrículas repetidas, aliases sobrepostos, divergências de dados pessoais e fontes AZ sem identidade inequívoca. O comando é somente de leitura e não imprime documentos ou nomes. Revise esses registros pela ficha RH antes de tratar prévias legadas como resultados conferidos.

A migração de unificação é irreversível por `db:rollback`, pois vínculos e fechamentos novos precisam ser preservados. Uma reversão do código deve manter o schema aditivo e ser conferida para compatibilidade com novos vínculos AZ.

## Validação

Os testes abrangem cadastro central, sincronização, desligamento, permissões, transferências por data, troca de turno/Promax, consumo por matrícula histórica, ambiguidades, fontes AZ, revisões de ambos os setores e consistência entre consulta/dashboard/chat. O teste Playwright `test/browser/employees_test.cjs` cobre os formulários DU/AZ, criação, movimentações, edição, identificação pública e layout móvel. Use um servidor e usuário no banco descartável de testes, com `BASE_URL`, `BROWSER_EMAIL` e `BROWSER_PASSWORD`.
