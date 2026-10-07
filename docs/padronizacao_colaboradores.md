# Padronização dos colaboradores DU e AZ — diagnóstico de origem

Análise do código anterior à refatoração em 07/10/2026. Este documento preserva o diagnóstico e as decisões de arquitetura que orientaram a implementação. O cadastro comum DU/AZ, as migrações e os consumidores foram implementados depois desta análise; consulte [o guia atualizado](colaboradores_e_cargos.md) para o funcionamento e a implantação. A análise usa código, schema e testes locais, sem auditoria dos cadastros de produção.

O objetivo é cadastrar cada pessoa uma vez e usar seu vínculo vigente para decidir quais informações, recursos e regras de variável se aplicam. DU e AZ continuam com suas particularidades operacionais.

## Diagnóstico com evidências

| Situação anterior | Evidência | Consequência |
| --- | --- | --- |
| Colaborador ainda significa, na prática, uma pessoa da DU. | `Employee` se relaciona com `Driver` e `Ajudante`; `EmployeeRole` e a constraint do banco aceitam somente ajudante, van e motorista. Não há setor no colaborador ou na vigência. | Operadores e ajudantes AZ não aparecem no cadastro central de RH. |
| O vínculo com RH é criado em uma única direção. | `EmployeeCareerRegistration` cria pessoa e cargo após criar motorista/ajudante; `EmployeesController#create` cria apenas pessoa e cargo. | Uma pessoa cadastrada diretamente no RH pode calcular variável por Promax, mas fica fora dos seletores da escala e do PCD, que enumeram os cadastros antigos. |
| Dados pessoais e situação têm várias fontes de gravação. | Os controllers antigos permitem editar nome, matrícula, CPF e nascimento; motorista/ajudante também permitem editar Promax. `retire!` atualiza somente o cadastro operacional. | Nome, identificação, código e situação podem divergir entre RH, operação e consulta. Editar Promax antigo não registra uma mudança no histórico de cargos. |
| Cargo vigente e identificação operacional podem vir de lugares diferentes. | `Pcd::Board#members` consulta cargo em `employee.role_on(date)`, mas nome e código em `person.nome` e `person.promax`. Os seletores da escala identificam a função pela tabela antiga. | Após uma movimentação, cargo pode estar correto enquanto código, nome ou rótulo exibido ainda refletem o cadastro antigo. |
| O portal público pede um tipo de cadastro. | `PublicVariableIdentity::PROFILES` oferece colaborador, motorista, ajudante, operador e az_ajudante. | A mesma pessoa DU pode ter mais de uma entrada e precisa entender a estrutura interna do sistema para se identificar. |
| AZ usa turno atual para consultar operações passadas. | `Operator` e `AzAjudante` têm somente `turno`; consulta, dashboard e chat usam esse valor para períodos históricos. | Uma troca de turno pode mudar o resultado de consultas antigas. Não há vigência de cargo/turno equivalente à DU. |
| Parte dos registros AZ é associada por nome. | `AzRvEmployeeMatching` busca nome normalizado ou truncado; a importação de WMS também resolve operadores pelo nome. | Homônimos, nomes truncados e mudanças de nome exigem conciliação. Nome não é uma identidade estável. |
| Os cálculos AZ são repetidos entre interfaces. | `AzConsultasController`, `AzDashboardService` e `PublicVariableContext` montam totais separadamente, embora reutilizem alguns serviços de componentes. | Mudanças de regra podem gerar números diferentes conforme a tela. Há diferenças concretas no tratamento de WMS, descritas abaixo. |
| A regra de progressão atual é específica da DU. | `EmployeeRole::PROGRESSAO` permite ajudante → van/motorista e van → motorista. | Acrescentar operador/AZ ao enum não basta: exigência de Promax, progressão e validações continuariam assumindo DU. |

O histórico DU já possui recursos que devem ser aproveitados: cargo e Promax por data, tarifas versionadas, revisões de fechamento e auditoria. A consulta DU e seu dashboard já compartilham `EmployeeVariableReport`; não é necessário reconstruir essa parte.

### Diferenças concretas em WMS

`AzConsultasController#show` e `AzDashboardService#operator_ranking` verificam `duration.to_f * 60 >= 10`, enquanto `PublicVariableContext#operator_context` verifica `duration.to_i >= 10`. A importação de `WmsTask` calcula duração pela diferença entre datas em segundos, e a validação exige no mínimo 10. Essa validação pode mascarar a diferença nos registros atuais, mas a unidade precisa ser definida e usada de forma consistente.

A consulta filtra `started_at: start_date..end_date`, usando datas; o dashboard usa início e fim do dia, incluindo a noite do último dia. Há teste específico do dashboard para WMS às 23h do dia 18. A padronização deve garantir que consulta, dashboard e chat usem o mesmo intervalo e resultado.

## Matriz de recursos a preservar

| Aspecto | Motorista / van DU | Ajudante DU | Operador AZ | Ajudante AZ |
| --- | --- | --- | --- | --- |
| Identidade e dados pessoais | Cadastro comum | Cadastro comum | Cadastro comum | Cadastro comum |
| Setor operacional | DU | DU | AZ | AZ |
| Cargo com vigência | Motorista ou van | Ajudante | Operador | Ajudante |
| Identificação específica | Promax com vigência | Promax com vigência | Identificadores das fontes AZ | Identificadores das fontes AZ |
| Turno A/B/C | Não exigido pelo modelo atual DU | Não exigido pelo modelo atual DU | Com vigência | Com vigência |
| Escala 5×2 | Elegível; depende da inscrição na escala | Elegível; depende da inscrição na escala | Não se aplica | Não se aplica |
| PCD | Conforme cargo e disponibilidade na data | Conforme cargo e disponibilidade na data | Não se aplica | Não se aplica |
| Meu consumo | Conforme atuação como motorista/van no período | Não se aplica ao período exclusivo de ajudante | Não se aplica | Não se aplica |
| Variável | Regras próprias de motorista/van | Regras próprias de ajudante DU | Regras próprias de operador AZ | Regras próprias de ajudante AZ |
| Fechamento atual | 21 do anterior a 20 | 21 do anterior a 20 | 19 do anterior a 18 | 19 do anterior a 18 |
| Dashboard do setor | DU / Mapas | DU / Mapas | AZ / Metas | AZ / Metas |

Elegibilidade para escala não significa inscrição automática. Cargo contratado também não é a mesma coisa que posição ocupada em uma saída: um motorista pode atuar excepcionalmente como ajudante no PCD sem ser promovido ou ter seu cargo cadastral alterado. O cálculo continua respeitando o histórico e as exceções operacionais já previstas.

Na AZ, preservar inclusive regras que não seguem uma simples divisão por turno: EFC dos ajudantes é compartilhada por A/B/C, suprimento se aplica ao turno A e remonte ao turno B. Unificar cadastro não autoriza alterar essas fórmulas, tarifas ou exclusões de domingos.

## Modelo recomendado

1. **Pessoa (`Employee`)**: identidade interna estável, nome, matrícula como texto, CPF normalizado, nascimento e situação cadastral. Todos os grupos pertencem a esse cadastro. Matrícula é identificação de negócio; os vínculos operacionais usam o ID interno para resistir a correções de matrícula.
2. **Vínculo operacional com vigência**: pessoa, setor DU/AZ, cargo, turno quando aplicável, início/fim, motivo e responsável. Recomenda-se evoluir `EmployeeRole`, aproveitando seu histórico existente, em vez de criar uma segunda história independente. Promax só é obrigatório para funções DU que o utilizam; AZ exige turno e pode ter identificadores próprios das integrações.
3. **Identificadores de integração**: códigos e aliases associados à pessoa com origem e, quando necessário, vigência. Promax DU mantém as regras atuais de propriedade por posição operacional e período. Nomes importados AZ são pistas para conciliar; correspondências ambíguas ficam pendentes de revisão.
4. **Regras de recursos e acesso**: recursos disponíveis são decididos pelo vínculo da pessoa e pela data/período. Permissões de quem está usando o sistema são decididas pelo usuário autenticado, setor e papel. O setor de `User` não deve ser usado como setor do colaborador.
5. **Relatórios de variável**: contrato comum de entrada e saída, com cálculo específico para cada perfil operacional. A DU reaproveita `EmployeeVariableReport`/`MapaRemuneracaoService`; AZ ganha relatórios de operador e ajudante que compõem os serviços existentes. Consulta, dashboard e chat consomem esses mesmos resultados.

Uma mudança de turno ou setor encerra a vigência anterior e abre outra na data informada. Não é necessariamente uma promoção: a progressão DU permanece uma política específica de carreira DU. Transferências entre setores exigem motivo e tratamento próprio, sem inventar uma hierarquia entre motorista e operador.

Como padrão inicial, manter um vínculo operacional principal por pessoa e data, tal como a DU já mantém um cargo vigente. Atuação excepcional no PCD é alocação diária. Se a operação precisar de vínculos simultâneos entre setores, isso deve ser modelado explicitamente antes de permitir sobreposição.

Um período que atravessa transferência de setor deve mostrar parcelas separadas, cada uma com sua janela de apuração. Não somar fechamentos DU de 21–20 e AZ de 19–18 como se fossem o mesmo intervalo.

O status global de uma pessoa precisa ter uma fonte única. Encerrar um vínculo DU por transferência para AZ não equivale a desligar a pessoa; desligamento e encerramento de vínculo são eventos diferentes. Datas reais de movimentação/desligamento devem ser registradas, sem presumir datas para o legado.

## Como ficaria no app

- **RH → Colaboradores**: lista de todas as pessoas, filtros DU/AZ, cargo, turno quando aplicável e situação; um formulário de cadastro e uma ficha por pessoa.
- **DU → Colaboradores**: visão filtrada do cadastro comum com recursos DU. Motoristas e ajudantes podem continuar como atalhos com filtros.
- **AZ → Colaboradores**: visão filtrada do mesmo cadastro, com operador/ajudante e turno. Os dashboards permanecem nas áreas de cada setor.
- **Ficha da pessoa**: identificação, histórico de vínculos e variável com componentes por perfil. Escala/PCD aparecem para vínculos DU elegíveis, consumo para motorista/van no período e turno/componentes AZ para vínculos AZ. Histórico anterior continua acessível após uma transferência.
- **Consulta pessoal/chat**: entrada comum pela identificação já usada no app; setor, cargo e turno são resolvidos pelo sistema. Se houver duplicidade, exibir encaminhamento para revisão em vez de escolher um cadastro arbitrariamente. Períodos históricos usam o vínculo da época.

Os rótulos para usuários podem ser “Ajudante · DU” e “Ajudante · AZ”. `az_ajudante` continua, durante a transição, como identificador técnico dos caminhos legados.

## Transição sugerida

### 1. Resolver inconsistências da DU e definir a fonte única

Centralizar cadastro, atualização de dados pessoais, movimentação e inativação em serviços que gravem identidade/vínculo de forma consistente. Os formulários e importações antigos passam por esses mesmos serviços; correções de Promax devem passar pelo histórico, não por edição isolada de coluna.

Enquanto escala e PCD dependerem das tabelas antigas, o cadastro pelo RH deve provisionar o vínculo de compatibilidade necessário na mesma transação, ou os módulos devem passar a consultar diretamente `Employee`. Não deixar o caminho RH gerar pessoas invisíveis para a operação.

Os adaptadores devem expor nome, código e cargo vigentes da mesma fonte. Não criar sincronizações dispersas entre callbacks de todos os modelos, que manteriam vários donos dos mesmos dados.

### 2. Incluir AZ no cadastro central

Adicionar setor/turno e regras condicionais ao histórico, incluindo migrations das constraints de banco. Vincular `Operator` e `AzAjudante` a `Employee` para compatibilidade. A migração precisa conferir CPF, matrícula e conflitos entre tabelas; homônimos não são fundidos automaticamente.

Preservar IDs antigos, associações de WMS, autonomias, feedbacks do Ciclo de Gente, importações e fechamentos. Matrículas AZ hoje são inteiros; transformar sua representação em texto não recupera zeros já perdidos. Datas iniciais desconhecidas continuam identificadas como legadas até revisão.

### 3. Padronizar consulta e cálculo

Criar resolução comum de identidade/vínculo e relatórios AZ compartilhados. Substituir a escolha manual de tabela no portal. Centralizar intervalos, unidades de duração, componentes e totais; preservar regras DU e AZ.

Fechamentos DU já registrados permanecem preservados. Estender esse padrão à AZ exige snapshots que incluam vínculo/turno, componentes, tarifas e fontes utilizadas, com revisões auditadas. Não apresentar cálculos reconstruídos como fechamentos históricos reais.

### 4. Migrar os módulos operacionais

Migrar escala para referência à pessoa e elegibilidade DU na data. Fazer PCD usar identidade estável e atributos vigentes, mantendo leitura das referências antigas em planos/importações e trilha de histórico.

Revisar vínculos polimórficos e consultas auxiliares antes de retirar tabelas antigas. Rotas antigas podem redirecionar para a ficha ou listagem filtrada, preservando links usados na operação. A remoção das tabelas vem depois da migração dos consumidores e da conferência dos dados.

## Permissões e verificações de aceite

O PCD já exige usuário DU ou administrador no backend. A escala restringe edição, mas sua leitura hoje bloqueia somente mecânicos. O dashboard DU de Mapas exige login sem um filtro específico de setor; o dashboard AZ permite AZ, supervisão e administração. Essas diferenças devem ser decididas como política de acesso e aplicadas igualmente em menu e endpoint. A exclusividade operacional de colaboradores DU na escala/PCD é independente de RH ou planejamento poderem consultar/gerenciar esse módulo.

Critérios para validar a implantação:

- Criar pessoa DU pelo RH e encontrá-la na escala/PCD; elegibilidade e disponibilidade ainda precisam ser respeitadas.
- Criar operador/ajudante AZ pelo cadastro comum e não oferecer recursos DU a esse vínculo.
- Atualizar dados pessoais uma vez e obter a mesma identificação na ficha, operação e consulta.
- Desligar uma pessoa e impedir nova atuação/identificação como ativa, preservando consultas históricas autorizadas.
- Promover ajudante DU → van → motorista e preservar códigos, cargos, bônus e fechamentos por data.
- Trocar turno AZ e manter o turno correto em cada operação histórica.
- Transferir DU → AZ preservando história DU e aplicando a regra AZ desde a data efetiva.
- Usar motorista como ajudante numa saída sem alterar o cargo contratado.
- Obter os mesmos componentes/totais em consulta, dashboard e chat para a mesma pessoa e intervalo, incluindo WMS no final do dia 18.
- Rejeitar/encaminhar vínculos ambíguos por nome/matrícula, sem fusão automática.
- Preservar a EFC compartilhada dos ajudantes AZ e as parcelas específicas de cada turno.
- Conferir acesso por URL além da visibilidade dos menus.

## Arquivos centrais para a implementação

- Cadastro/história DU: `app/models/employee.rb`, `app/models/employee_role.rb`, `app/models/concerns/employee_career_registration.rb`, `app/controllers/employees_controller.rb`.
- Cadastros anteriores: `app/models/{driver,ajudante,operator,az_ajudante}.rb` e respectivos controllers.
- Escala/PCD: `app/models/time_off_membership.rb`, `app/services/time_off/people.rb`, `app/services/time_off/personal_schedule.rb`, `app/services/pcd/board.rb`.
- Identificação/chat: `app/services/public_variable_identity.rb`, `app/services/public_variable_context.rb`.
- Variável: `app/services/employee_variable_report.rb`, `app/services/mapa_remuneracao_service.rb`, `app/controllers/az_consultas_controller.rb`, `app/services/az_dashboard_service.rb`, serviços `az_helper_*` e `az_operator_on_demand_service.rb`.
- Integrações: `app/models/concerns/az_rv_employee_matching.rb`, `app/models/wms_task.rb`, `app/models/people_cycle_feedback.rb`, `app/services/people_cycle_import_service.rb`, `app/services/gasola/team_report.rb`.
- Navegação: `app/views/shared/_navbar.html.erb`, `app/helpers/navbar_helper.rb`.

## Validação realizada nesta análise

Foram executados sete arquivos de testes existentes: controllers de colaboradores, consulta AZ e dashboard AZ; relatórios DU; contextos de consumo/folgas; e escala pessoal. Resultado com host de rotas configurado apenas no processo: **56 testes, 356 assertions, sem falhas ou erros**.

Na execução padrão de `bin/rails test`, o mesmo recorte teve um erro preexistente de configuração: `EmployeesControllerTest#test_dashboard_and_chat_use_the_employee_role_for_van_recarga` gera uma URL absoluta no contexto de consumo sem host definido. A repetição definiu `Rails.application.routes.default_url_options[:host] = "example.test"` em memória; nenhum arquivo de configuração foi alterado.

Uma reprodução adicional no banco de testes, dentro de transação revertida, confirmou:

- Pessoa e cargo criados pelo caminho de RH ficaram com zero motoristas/ajudantes vinculados.
- Editar nome e Promax no motorista deixou os valores anteriores na pessoa/vigência RH.
- Inativar o motorista manteve `Employee.active = true` e a identificação pública como colaborador continuou funcionando.
- Uma tarefa WMS às 23h de 18/09/2026 ficou fora do filtro atual da consulta e dentro do filtro atual do dashboard.

Esses testes descrevem casos locais controlados. Não medem quantos cadastros reais estão inconsistentes, e o sucesso da suíte existente não cobre todos os critérios de aceite propostos.
