# Colaboradores, cargos e variável

Acesse **RH → Colaboradores** (RH, supervisão ou administração). Cadastre a pessoa e o cargo inicial com sua data efetiva. Para uma promoção, abra a pessoa e use **Registrar mudança de cargo**. Informe cargo, Promax, data e motivo. O cargo anterior termina no dia precedente. Nenhuma data de promoção é presumida.

- Cargos: ajudante, motorista de van, motorista.
- O cargo e o código Promax têm vigência. A data da operação decide o cálculo, inclusive em importações atrasadas.
- O bônus exige pelo menos 15 mapas e devolução de até 3%, separadamente por cargo dentro do fechamento (21 a 20). Mapas de van e motorista não são somados para atingir o mínimo.
- Van recebe bônus. Um mapa de van marcado como recarga paga caixas e entregas, entra nos volumes/devolução e não recebe tarifa de recarga. A marcação original permanece visível.
- Permanecem as regras de fator já existentes: fator 2 divide caixas/entregas por dois; a regra de fator 0 com pelo menos dois PDVs permanece exclusiva de motorista.
- Tarifas usam a vigência na data de cada mapa. Para o bônus do cargo, usa-se a tarifa geral na última data de mapa desse cargo no fechamento.

## Histórico e implantação

Execute `bin/rails db:migrate` no ambiente de destino. As migrações:

1. Criam colaboradores e vigências legadas a partir dos cadastros existentes. O antigo Promax 86 é convertido em cargo van apenas nesta migração; não há identificação por esse número na aplicação. Não se inventam datas de admissão ou promoção: a vigência legada tem início desconhecido.
2. Guardam as tarifas disponíveis como referência inicial. Não é possível reconstruir tarifas históricas que não tenham sido guardadas antes.
3. Registram as prévias dos fechamentos cujo dia 20 já passou, usando a regra anterior, inclusive suas particularidades para van. São **referências legadas, não comprovantes de pagamento**. Isso preserva a consulta anterior enquanto novas regras são implantadas.

Os cadastros não são fundidos automaticamente por nome. Matrículas ambíguas precisam de revisão do RH. Ao solicitar um vínculo, o sistema abre uma página de conferência com os dois colaboradores, seus cargos, Promax, mapas, as três últimas variáveis e fechamentos. O CPF precisa coincidir e a direção é normalizada: o cadastro principal é identificado antes da confirmação, independentemente de qual dos dois foi aberto. A posição pode ser invertida na própria página. A operação só ocorre após informar a data da progressão e o motivo; os fechamentos dos dois cadastros são mesclados no principal, com nova revisão quando houver conflito de período.

Para as duas promoções em discussão: registre primeiro van → motorista na pessoa atual, depois ajudante → van na outra pessoa, com suas datas reais. Não altere o Promax antigo para tentar mover os mapas. Se houver outro cadastro operacional já existente da mesma pessoa, use o vínculo de cadastro em vez de criar uma segunda movimentação manual.

## Fechamentos e correções

**Registrar fechamento ou revisão** salva os mapas, vigências, tarifas e totais usados, com responsável e motivo. Cada revisão tem um novo número e preserva as anteriores. Uma correção de data/cargo fica auditada e não modifica resultados já registrados; para aplicá-la a um período registrado, gere outra revisão desse período.

A consulta e o chat usam a última revisão registrada. O dashboard mensal também usa os resultados registrados; filtros de quinzena são prévias do recorte, não rateios do fechamento. Períodos abertos são calculados pela história cadastrada. Mapas sem data/cargo compatível ou com vínculo ambíguo são sinalizados; impedem registrar um fechamento incompleto.

O registro de um fechamento não significa pagamento, envio à folha ou autorização bancária.

## Outros cadastros e importações

Os formulários de motorista/ajudante também exigem data inicial e criam o vínculo com RH. No CSV, adicione `inicio_cargo` no formato `AAAA-MM-DD`; para motorista, `cargo` aceita `motorista` ou `van` (ausência mantém motorista). Um erro aborta todo o arquivo. Pessoas existentes devem ser movimentadas pelo RH.

Novos parâmetros e alterações de valor geram versões. Nome e categoria identificam o histórico; não podem ser renomeados ou excluídos pelos formulários. Mudanças retroativas alteram prévias abertas, mas não sobrescrevem fechamentos registrados.

## Validação

Testes cobrem datas de promoção, troca de Promax, conflitos de código, correção de vigência, recarga de van, bônus separado (inclusive van → motorista), tarifas por data, revisões imutáveis, vínculo de cadastros, rollback de importação, controle de acesso, consulta, dashboard e contexto do chat.
