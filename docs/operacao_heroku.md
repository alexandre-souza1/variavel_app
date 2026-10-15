# Publicação no GitHub e Heroku

O remoto `origin` publica no GitHub; `heroku` publica no app `workstation-app-foz`.
O `Procfile` executa `bundle exec rails db:migrate` na fase de release.

Antes do envio, valide os testes relevantes, `git diff --check` e os arquivos do commit.
O `.env`, seus arquivos locais de ambiente e `config/master.key` permanecem fora do Git.

```sh
git push origin master
git push heroku master
heroku releases --app workstation-app-foz --num 2
heroku ps --app workstation-app-foz
```

Confirme o hash publicado nos dois remotos, o sucesso da fase de release e a resposta HTTP do app.
Para verificações via Rails runner, retorne somente status, versões de migração ou booleanos necessários.

## Configurações e privacidade

As Config Vars pertencem ao ambiente do Heroku e são injetadas no processo do app. O envio Git
não precisa consultar nem imprimir seus valores. O carregamento local pelo `dotenv-rails`
também não exige exibir o conteúdo do `.env`.

O comando `heroku releases:info` sem `--json` consulta as Config Vars da release e imprime
seus valores, além dos metadados. Por isso, use a listagem `heroku releases` para a validação
normal de um deploy. Evite saídas integrais de `heroku config`, `ENV`, arquivos de ambiente
ou respostas de API que contenham credenciais.

Quando uma consulta adicional for necessária, filtre campos permitidos antes de exibir a saída.
Dados de autenticação não devem ser incluídos em logs, commits, mensagens ou documentação.

Referências: [releases](https://devcenter.heroku.com/articles/releases#listing-release-history)
e [Config Vars](https://devcenter.heroku.com/articles/config-vars).
