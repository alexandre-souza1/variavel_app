# Variável App

Aplicação web da operação LOG20 Foz. O sistema centraliza rotinas de frota, manutenção, checklists, tarefas, consultas operacionais, financeiro e gestão de pessoas.

## Stack

- Ruby 3.3.5
- Ruby on Rails 7.1
- PostgreSQL
- Puma
- Hotwire, Turbo e Stimulus
- Importmap e Sprockets/SassC
- Bootstrap e Bootstrap Icons
- Action Cable com Redis
- Active Storage com armazenamento local, Amazon S3 ou Cloudinary
- Testes com Minitest, Capybara e Selenium

O fuso horário da aplicação é `Brasilia` e o timezone padrão do banco é UTC.

## Principais módulos

### Operação e frota

- Cadastro e controle de placas, motoristas, operadores e ajudantes.
- Disponibilidade diária da frota, com posições, depósito, indisponibilidade e rotas especiais.
- Dimensionamento da frota e placas padrão por posição.
- Fechamento manual e automático da disponibilidade.
- Ajuste automático no fechamento: placas disponíveis no depósito podem preencher posições vazias, com observação e histórico da movimentação.
- Geração de PDF, notificações internas e envio por e-mail da disponibilidade travada.
- Consumo de combustível e mapas operacionais.

### Manutenção e segurança

- Checklists e modelos de checklist.
- Respostas, defeitos, fotos, histórico e exportação para Excel.
- Tarefas de mecânica e atividades relacionadas.
- Importação e processamento de testes de estresse.

### Gestão de tarefas e rotinas

- Planos de ação, buckets, tarefas, responsáveis, etiquetas, comentários e listas de tarefas.
- Rotinas, indicadores, metas, valores, comentários e geradores a partir de templates.
- Notificações de atribuição e vencimento.

### Financeiro

- Invoices, notas fiscais, fornecedores, centros de custo e categorias orçamentárias.
- Rateio de notas fiscais e metas de invoices.
- Dashboard financeiro.
- Leitura de documentos fiscais com AWS Textract.
- Geração de comprovantes em PDF.

### Consultas e importações

- Consultas operacionais e consultas AZ.
- Importação de CSV e arquivos Excel.
- Downloads, QR codes e arquivos anexos.
- Integração opcional com Microsoft Graph/OneDrive/SharePoint.

## Requisitos locais

- Ruby 3.3.5
- Bundler 2.5 ou compatível
- PostgreSQL 9.3+
- Node.js/npm, quando necessário para ferramentas auxiliares do projeto
- Redis, caso Action Cable seja utilizado localmente

Confira a versão do Ruby em `.ruby-version` e no `Gemfile` antes de iniciar.

## Instalação

Clone o projeto e instale as dependências:

```bash
git clone git@github.com:alexandre-souza1/variavel_app.git
cd variavel_app
bundle install
```

Configure o PostgreSQL. O ambiente de desenvolvimento usa o banco `variavel_app_development`; o ambiente de testes usa `variavel_app_test`. A conexão pode ser ajustada em `config/database.yml` ou fornecida por `DATABASE_URL`.

Crie e prepare o banco:

```bash
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

O seed cria o usuário técnico `anon@system.local` com uma senha aleatória. Em ambientes compartilhados, altere ou remova esse usuário conforme a política de acesso da empresa.

Inicie o servidor:

```bash
bin/rails server
```

Acesse `http://localhost:3000`.

## Variáveis de ambiente

As variáveis dependem dos recursos habilitados no ambiente.

### Banco e aplicação

```text
DATABASE_URL
RAILS_MASTER_KEY
RAILS_MAX_THREADS
RAILS_LOG_LEVEL
```

### Active Storage

Para Amazon S3:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

Para o processamento de documentos com Textract:

```text
AWS_TEXTRACT_REGION       # padrão: us-east-1
AWS_TEXTRACT_BUCKET
```

Para Cloudinary, quando o serviço for selecionado:

```text
CLOUDINARY_CLOUD_NAME
CLOUDINARY_API_KEY
CLOUDINARY_API_SECRET
```

### E-mail

O envio SMTP é habilitado quando `SMTP_ADDRESS` está configurada:

```text
SMTP_ADDRESS
SMTP_PORT                  # padrão: 587
SMTP_DOMAIN
SMTP_USERNAME
SMTP_PASSWORD
SMTP_AUTHENTICATION         # padrão: plain
SMTP_SSL                   # padrão: false
SMTP_ENABLE_STARTTLS_AUTO  # padrão: true
MAILER_FROM                # padrão: workstation@example.com
```

### Microsoft Graph / OneDrive

```text
AZURE_CLIENT_ID
AZURE_CLIENT_SECRET
AZURE_TENANT_ID
AZURE_USER_ID
```

### Action Cable

```text
REDISCLOUD_URL
ACTION_CABLE_URL
```

Não versionar `.env`, chaves, tokens ou credenciais. Em produção, configure os valores no provedor de hospedagem.

## Testes

Execute toda a suíte com:

```bash
bin/rails test
```

Exemplos de suítes específicas:

```bash
bin/rails test test/models/invoice_test.rb
bin/rails test test/services/fleet_availabilities/daily_opening_test.rb
bin/rails test test/controllers/fleet_availabilities_controller_test.rb
bin/rails test test/mailers/fleet_availability_mailer_test.rb
```

Os testes usam o banco `variavel_app_test`. Para testes de sistema, o projeto utiliza Capybara e Selenium.

## Disponibilidade diária da frota

A rotina é executada pela tarefa:

```bash
bin/rails fleet_availabilities:daily
```

Ela:

1. Fecha disponibilidades vencidas ou que atingiram o horário de fechamento.
2. Procura posições vazias dentro do dimensionamento.
3. Move placas em `exchange`/depósito para essas posições, quando disponíveis.
4. Registra uma observação na placa movimentada e cria o histórico da alteração.
5. Trava a disponibilidade.
6. Cria a disponibilidade do próximo dia quando necessário.
7. Envia notificações internas e e-mail quando os destinatários estão configurados.

Os horários são configurados no painel de disponibilidade. Como a rotina verifica se o horário já foi atingido, ela pode ser executada por um Scheduler a cada 10 minutos; o fechamento ocorrerá na primeira execução posterior ao horário configurado.

Para executar localmente:

```bash
bin/rails fleet_availabilities:daily
```

Também existe o job `FleetAvailabilitiesDailyJob`, que executa o mesmo serviço quando chamado por um adaptador de jobs.

## Deploy no Heroku

O deploy é feito pelo remote `heroku`:

```bash
git push heroku master
```

O Scheduler do Heroku deve executar:

```bash
bundle exec rails fleet_availabilities:daily
```

Recomenda-se uma frequência de 10 minutos ou menor. O horário exibido pelo Scheduler pode estar em UTC, mas a aplicação interpreta o fechamento no fuso `Brasilia`.

Configurações importantes no Heroku:

- `DATABASE_URL` fornecida pelo PostgreSQL da aplicação.
- `RAILS_MASTER_KEY`, se forem usados credentials criptografados.
- Variáveis AWS, SMTP, Redis, Azure e Cloudinary conforme os módulos habilitados.
- Scheduler configurado para a tarefa diária da frota.

Para acompanhar logs:

```bash
heroku logs --tail --app NOME_DA_APP
```

## Arquitetura de pastas

```text
app/controllers/   Fluxos HTTP e autorização
app/models/        Regras de domínio e persistência
app/services/      Casos de uso e integrações
app/jobs/          Processamentos assíncronos
app/mailers/       E-mails transacionais
app/pdfs/          Documentos PDF gerados pela aplicação
app/javascript/    Controllers Stimulus e comportamento do front-end
app/views/         Interfaces HTML e templates de e-mail
app/assets/        SCSS, imagens e assets compilados
config/            Rotas, ambientes, banco, storage e inicializadores
db/                Migrações, schema e seeds
lib/tasks/         Tarefas Rake, incluindo a rotina diária da frota
test/              Testes automatizados e fixtures
```

## Arquitetura de assets SCSS

O entrypoint é `app/assets/stylesheets/application.scss`. A ordem dos imports é determinística:

- `custom/_index.scss` carrega variáveis, tokens e breakpoints.
- `components/_index.scss` carrega componentes compartilhados.
- `pages/_index.scss` carrega estilos específicos das telas.
- Os overrides de tema escuro, calendário e utilitários ficam nas camadas finais.

Ao criar novos estilos, prefira o diretório correspondente ao escopo do componente ou da página em vez de adicionar regras diretamente ao arquivo principal.

## Segurança e operação

- As rotas da aplicação usam autenticação Devise quando aplicável.
- Não publique credenciais no repositório.
- Revise permissões antes de habilitar integrações externas.
- Use armazenamento persistente para anexos em produção; o disco local do dyno não deve ser tratado como permanente.
- Acesse a rota `/up` para verificar a saúde básica da aplicação.
