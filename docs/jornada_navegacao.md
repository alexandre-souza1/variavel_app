# Revisão da jornada de navegação

## Critérios

- **Início** abre `/variaveis`, sem redirecionamento automático por setor.
- `/` continua sendo a entrada automática para o painel do setor após o acesso. O nome do usuário na barra de navegação usa essa entrada.
- **Voltar** e **Cancelar** têm destinos explícitos, inclusive quando a página é aberta por um link direto.
- O retorno à lista mantém os filtros e a paginação nos fluxos de lançamentos; na frota, mantém o dimensionamento selecionado.
- Após as operações revisadas de salvar, excluir, travar e destravar, o redirecionamento usa uma nova requisição GET (`303 See Other`).

## Problemas encontrados e ajustes

| Jornada | Problema | Comportamento revisado |
| --- | --- | --- |
| Módulos → início | Botões apontavam para `/`, que redireciona conforme o setor e pode retornar à mesma tela. | “Voltar ao início” e a marca Workstation abrem `/variaveis`. |
| Nome do usuário → painel | Usuários de DU/AZ eram enviados ao dashboard da Frota. | Abre a entrada automática do setor em `/`. |
| Dashboard de Mapas → voltar | Retornava ao dashboard da Frota, sujeito a restrições de acesso. | Retorna ao início. |
| Lançamentos → detalhe → editar → salvar | Perdia filtros, página e origem no dashboard. | A origem acompanha os links, o formulário, os erros de validação e o redirecionamento após salvar. |
| Editar lançamento → cancelar | Retornava à lista geral. | Retorna ao lançamento, que mantém o caminho para a origem. |
| Excluir lançamento | Retornava à lista sem filtros. | Retorna à lista ou ao dashboard de origem. |
| Frota → disponibilidade → voltar | Perdia o dimensionamento selecionado. | Mantém o período; links diretos usam o dimensionamento da data do registro. |
| Frota → configuração → salvar | Perdia o período da listagem. | Mantém o dimensionamento selecionado. |
| Editar plano → voltar/cancelar | Retornava à lista de planos. | Retorna ao plano em edição. |
| Importação de colaboradores/parâmetros → voltar | Saía do módulo e abria a entrada automática. | Retorna ao cadastro correspondente. |
| Histórico de checklists → voltar | Saía do módulo. | Retorna aos checklists. |
| Relatório de checklists | Botão prometia um relatório, mas abria a página inicial. | Atalho removido; o histórico continua disponível. |
| Dashboard AZ → consulta individual → trocar período → voltar | Retornava ao formulário de consulta. | Mantém a origem e os filtros do dashboard, tanto para operadores quanto para ajudantes. |
| Checklist com alterações → sair | A proteção de saída cobria somente o descarregamento da página; o cancelamento explícito podia confirmar duas vezes. | Também cobre visitas do Turbo e reconhece o cancelamento já confirmado. Os listeners são removidos ao desconectar. |

## Validação

As regressões de navegação estão em `test/controllers/navigation_journeys_test.rb`. Cobrem links, respostas, filtros, cancelamento, validação de formulários, exclusão e rejeição de destinos de retorno inválidos. Os destinos aceitos são caminhos locais específicos de cada jornada, sem dependência do histórico do navegador ou do cabeçalho Referer.

```sh
PARALLEL_WORKERS=1 bin/rails test test/controllers/navigation_journeys_test.rb
node --test test/javascript/before_leave_controller_test.mjs
```

O teste JavaScript verifica proteção de saída, confirmação recusada/aceita, autosave, cancelamento explícito, envio bloqueado e reconexão do controller. A validação automatizada não substitui a verificação do botão físico de voltar no aplicativo Android.
