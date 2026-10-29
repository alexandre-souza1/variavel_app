# Relatório gerencial financeiro

Em **Financeiro → Dashboard**, selecione **mês e ano**, aplique o filtro e clique em **Relatório gerencial**. Administradores e contas do setor Financeiro podem selecionar um setor ou todos os autorizados. As demais contas mantêm o escopo financeiro permitido pelo cadastro.

O PDF usa o mesmo formato do relatório gerencial do dashboard Mapas: A4 horizontal, gráficos vetoriais, tabelas e alertas. É gerado no servidor com Prawn, sem Gemini, sem depender de chave de IA e sem alterar lançamentos ou metas.

## Período e filtros

- Mês e ano são obrigatórios. Sem ambos, o dashboard não oferece o download. A URL direta `invoices/dashboard.pdf` também valida o período antes de consultar lançamentos e retorna HTTP 422 se faltar um campo ou se ele for inválido.
- São aceitos meses de 1 a 12 e anos de 2000 a 2100. Cada relatório cobre um único mês civil por data de emissão. A comparação usa somente o mês imediatamente anterior, com os mesmos filtros, nunca todo o histórico do app.
- O documento identifica datas, setores e centro de custo. Metas são selecionadas pela vigência no mês e ano consultados e pelo setor, incluindo todas as categorias agrupadas em cada meta. Uma vigência iniciada depois do período consultado nunca é aplicada retroativamente.
- Um centro de custo seleciona as notas que o contêm e considera o total dessas notas uma vez, como no dashboard. O relatório avisa que esse recorte não equivale ao realizado de todo o setor e não reduz a meta setorial. As tabelas de centros de custo usam os valores rateados em `InvoiceNumber.amount`.
- O PDF revalida login, conta ativa, acesso ao Financeiro, setor e centro de custo. IDs ou filtros enviados manualmente não ampliam o acesso.

## Configuração das metas mensais

Em **Metas mensais**, cada indicador aparece uma única vez na tabela padrão dos cadastros, com setor, categorias e valor usado no mês atual. A ação **Histórico da meta** abre os valores anteriores no modal padrão; alterações futuras aparecem como agendamentos e não substituem o valor atual antes do mês escolhido. Indicadores sem meta aplicável ao mês aparecem como **Sem meta definida**.

Em **Novo indicador**, informe nome, setor, categorias, valor mensal e **A partir de**. As categorias disponíveis acompanham o setor escolhido. O valor continua automaticamente nos meses seguintes, inclusive na virada do ano.

Para mudar o valor, use **Alterar meta**: informe o valor mensal e o mês inicial. Nome e setor são mantidos pelo sistema; as categorias podem ser alteradas na seção recolhida do formulário. Meses anteriores ao escolhido são preservados, e alterações futuras já agendadas continuam valendo. Se já existir um registro com o mesmo mês inicial, ele é atualizado sem criar duplicatas. A gravação do valor e das categorias é atômica: erros não deixam alterações parciais.

Os cadastros mensais antigos e os intervalos sem cadastro são preservados. Na migração, apenas o registro mais recente de cada nome e setor fica sem término. Términos preenchidos posteriormente na configuração antiga continuam sendo respeitados; salvar uma alteração no novo formulário faz o valor continuar nos meses seguintes. No histórico, a meta atual fica em destaque e os valores anteriores aparecem em uma linha do tempo compacta. A seção recolhida **Gerenciar registros** reúne as exclusões; excluir um registro afeta os relatórios dos meses que o utilizam. Dashboard, PDF e assistente usam a mesma seleção de meta aplicável.

## Avaliação técnica

O documento mostra gasto, quantidade e valor médio dos lançamentos, comparação anterior, metas excedidas e gastos sem cobertura de meta. Cada meta tem realizado, previsto, percentual utilizado, saldo ou excesso em reais, categorias, cinco maiores fornecedores, cinco maiores centros de custo e cinco documentos de maior impacto, com observações cadastradas limitadas a 500 caracteres.

O diagnóstico compara as mesmas categorias no mês anterior. A variação do gasto é decomposta em efeito do número de lançamentos e efeito do valor médio por lançamento:

- Efeito de volume: `(quantidade atual − quantidade anterior) × valor médio anterior`.
- Efeito de valor médio: `quantidade atual × (valor médio atual − valor médio anterior)`.

Essa decomposição é contábil: quantidade de notas não é quantidade física, e valor médio por nota não comprova variação de preço unitário. Quando há meta anterior de mesmo nome, setor e composição de categorias, o relatório também mostra a mudança no orçamento. Não compara metas de composição diferente como equivalentes.

Concentração de fornecedores e grandes lançamentos aponta documentos para investigação. Os textos recomendam conferir quantidades, preços, ordens de serviço, gastos extraordinários e competência; não afirmam uma causa não comprovada. Não existe meta individual de categoria ou fornecedor quando o orçamento é agrupado.

Os quatro gráficos mostram categorias, fornecedores, utilização das metas e maiores variações de categoria sobre o mês anterior, com até dez entradas por gráfico. A comparação completa de categorias e as páginas de todas as metas complementam esses rankings. O ranking geral de documentos mostra até vinte notas. Totais e atingimento consideram todos os registros do mês autorizado.

Metas sobrepostas não são somadas. Sem metas, o PDF mantém a avaliação dos gastos e informa que não há atingimento calculável. Sem lançamentos anteriores, a comparação fica sem base. Mês em andamento/futuro é sinalizado como parcial; saldo positivo ainda não comprova economia no fechamento. Valores lançados não comprovam pagamento.

## Validação

`PARALLEL_WORKERS=1 bin/rails test test/services/invoice_management_report_test.rb test/controllers/invoice_management_reports_controller_test.rb`

Os cenários cobrem período obrigatório inclusive pela URL direta, ano correto das metas, categorias agrupadas, metas sobrepostas, decomposição da variação, rateios sem duplicação, restrições de acesso, ausência de dados, mês parcial e PDF sem escrita ou chamada ao Gemini.
