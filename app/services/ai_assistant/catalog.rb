module AiAssistant
  class Catalog
    S = ->(description) { { type: 'string', description: description } }
    I = { type: 'integer' }.freeze
    PAGE = { page: { type: 'integer', description: 'Página a partir de 1, até 20 resultados' } }.freeze
    PERIOD = { from: S.call('Início inclusivo YYYY-MM-DD'), to: S.call('Fim inclusivo YYYY-MM-DD') }.freeze

    def self.entries
      @entries ||= begin
        query = { query: S.call('Trecho do nome, título ou descrição') }
        month = { month: S.call('Mês de referência YYYY-MM; respeita o fechamento de cada módulo') }
        sector = { sector: S.call('Setor autorizado; financeiro usa frota, rota, as, rh, seguranca, gestao, financeiro ou armazem; colaboradores usam du ou az') }
        [
          entry('task_details', :tasks, 'Consulta os dados atuais de uma tarefa acessível: descrição, responsáveis com IDs, início, prazo, situação, lembrete e recorrência. Use antes de propor alterações.', task_id: I),
          entry('daily_briefing', :tasks, 'Resumo do dia de hoje, agenda e prioridades: tarefas pessoais, GEROT, saldo das metas financeiras do mês e alertas relevantes ao setor. Use para "o que tenho para hoje", "resuma meu dia" e "onde preciso ter atenção". Admin pode escolher outro setor ou all; demais usuários usam seu próprio setor.', sector: { type: 'string', enum: %w[fleet du warehouse hr safety finance planning all] }),
          entry('financial_summary', :finance, 'Gastos por período de emissão, categorias e fornecedores; totais exatos dentro dos setores autorizados.', **PERIOD, **sector),
          entry('list_invoices', :finance, 'Busca lançamentos/notas por fornecedor, categoria, centro de custo, código, vencimento ou emissão. Não determina se foram pagos.', **PAGE, **PERIOD, **sector, **query, category_id: I, cost_center_id: I, due_from: S.call('Vencimento inicial YYYY-MM-DD'), due_until: S.call('Vencimento final YYYY-MM-DD')),
          entry('invoice_details', :finance, 'Detalha um lançamento autorizado e seu rateio, fornecedor e solicitante.', invoice_id: I, **PAGE),
          entry('financial_goals', :finance, 'Metas financeiras e gastos realizados nas categorias de cada meta no mês civil.', **PAGE, **month, **sector),
          entry('list_suppliers', :finance, 'Fornecedores encontrados nos lançamentos autorizados, com totais do período.', **PAGE, **PERIOD, **query),
          entry('financial_catalog', :finance, 'Categorias e centros de custo disponíveis para localizar identificadores e filtrar consultas financeiras.', **PAGE, **query),
          entry('list_employees', :employees, 'Busca colaboradores por nome ou matrícula; retorna cargo, turno e setor vigentes. Não retorna CPF ou nascimento.', **PAGE, **query, **sector, status: S.call('active, archived ou all'), cargo: S.call('Cargo'), turno: I),
          entry('employee_details', :employees, 'Consulta histórico de funções e fechamentos salvos do colaborador nos setores autorizados.', employee_id: I, **PAGE, **month, **sector),
          entry('employee_variable', :employees, 'Consulta remuneração variável de um colaborador em um mês e setor autorizado, distinguindo prévia de fechamento salvo. Localize antes por list_employees.', employee_id: I, **month, **sector),
          entry('employee_feedbacks', :employees, 'Feedbacks do Ciclo de Gente do colaborador autorizado. Sem ano usa o atual; não substitui por outro ano.', employee_id: I, year: I, **PAGE),
          entry('time_off', :employee_schedules, 'Escala de um colaborador DU, com folgas, DSR, férias e próxima folga. Localize por list_employees.', employee_id: I, **month, date: S.call('Referência YYYY-MM-DD')),
          entry('time_off_team', :time_off, 'Situação da equipe DU em uma data: trabalho, folga, DSR, férias ou indisponibilidade, sem motivos pessoais.', **PAGE, **query, date: S.call('YYYY-MM-DD'), status: S.call('working, off, dsr, vacation, unavailable ou pending')),
          entry('du_summary', :du, 'Indicadores DU: mapas, caixas, PDVs, recargas e devolução no fechamento ou intervalo. Não é total de pagamentos.', **PERIOD, **month, **PAGE),
          entry('az_summary', :az, 'Indicadores, resultados e remuneração por cargo do Armazém no fechamento de 19 a 18 ou intervalo, por turno.', **PERIOD, **month, **PAGE, turno: I),
          entry('fuel_consumption', :consumption, 'Consumo Gasola, km/l, metas, emissões e comparações por motorista ou placa. Informa atualização e dados parciais.', **PERIOD, **month, **PAGE, registration: S.call('Matrícula'), plate: S.call('Placa'), fuel: S.call('Combustível')),
          entry('list_plates', :plates, 'Busca veículos cadastrados por placa, setor, tipo e perfil.', **PAGE, **query, sector: S.call('Setor da placa, por exemplo ROTA ou ARMAZEM'), status: S.call('active, archived ou all')),
          entry('fleet_dimensioning', :dimensioning, 'Dimensionamento vigente na data, quantidades e placas padrão por rota.', date: S.call('YYYY-MM-DD')),
          entry('tire_status', :tires, 'Pneus instalados de uma placa ou pneus no limite de recape; consulta somente leitura à integração Prolog.', **PAGE, plate: S.call('Placa; sem placa lista pneus para recape')),
          entry('stress_events', :stress, 'Eventos de stress test/rodagem por data, placa ou motorista.', **PAGE, **PERIOD, **query),
          entry('list_checklists', :checklists, 'Busca checklists permitidos (próprios; admin e supervisor veem histórico geral).', **PAGE, **PERIOD, plate: S.call('Placa'), status: S.call('draft ou completed')),
          entry('checklist_details', :checklists, 'Observações, defeitos e respostas de um checklist autorizado, sem anexos.', checklist_id: I, **PAGE),
          entry('list_routines', :routines, 'Busca GEROTs autorizados por nome, plano e situação.', **PAGE, **query, plan_id: I, status: S.call('open, closed, archived ou all')),
          entry('routine_details', :routines, 'Indicadores e metas do GEROT autorizado, com valor calculado, preenchimento e desvios. Não cria valores.', routine_id: I, **PAGE, **query),
          entry('routine_values', :routines, 'Preenchimentos de um GEROT autorizado por data e indicador; nunca cria valores faltantes.', routine_id: I, indicator_id: I, **PAGE, **PERIOD),
          entry('list_meetings', :meetings, 'Busca atas acessíveis, por título, plano ou período. Visibilidade do plano não libera atas privadas.', **PAGE, **PERIOD, **query, plan_id: I),
          entry('meeting_details', :meetings, 'Resumo, decisões e pendências da ata autorizada. Não acessa áudio nem conversas do assistente.', meeting_id: I),
          entry('list_documents', :documents, 'Localiza padrões, LUPs e matrizes cadastradas por título/descrição/setor. Não lê o conteúdo dos arquivos.', **PAGE, **query, category: S.call('PADRÃO, LUP ou MATRIZ'), sector: S.call('Setor do documento')),
          entry('public_resources', :public_resources, 'Consulta localização das placas no pátio ou catálogo de rotogramas; não interpreta o conteúdo dos PDFs.', **PAGE, **query, resource: { type: 'string', enum: %w[parking routes] }),
          entry('pcd_board', :pcd, 'PCD SALAS salvo ou prévia da data: equipes, placas, salas, horários e lacunas.', **PAGE, date: S.call('YYYY-MM-DD')),
          entry('ai_usage', :admin, 'Consumo de IA por modelo, recurso e pessoa e cotas estimadas. Nunca consulta perguntas ou respostas de usuários.', period: { type: 'string', enum: %w[7 30 90] }, **PAGE, **query),
          entry('ai_configuration', :admin, 'Modelo prioritário, alternativas, duração máxima de reuniões e limites configurados de IA; nunca retorna a chave.'),
          entry('list_accounts', :admin, 'Contas do sistema, setores, perfis e situação. Nunca retorna senhas, tokens ou conversas.', **PAGE, **query, sector: S.call('fleet, du, warehouse, hr, safety, finance ou planning'), status: S.call('active, archived ou all'))
        ].index_by { |entry| entry[:declaration][:name] }.freeze
      end
    end

    def self.entry(name, area, description, **properties)
      { area: area, declaration: { type: 'function', name: name, description: description,
        parameters: { type: 'object', properties: properties } } }
    end
    private_class_method :entry
  end
end
