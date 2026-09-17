# Workstation para Android

Aplicativo Kotlin/Hotwire Native 1.3.1 para Android 9 (API 28) ou superior. Usa o Rails em `https://workstation-app-foz-f23ff3447c33.herokuapp.com/` e precisa de internet. Inclui notificações push com Firebase Cloud Messaging; não implementa operação offline.

O nome exibido é **Workstation**. O ícone utiliza `app/assets/images/icon-512x512.png`, autorizado como alternativa ao `public/favicon.ico` vazio, e tem versão adaptativa para o launcher. O identificador `br.com.log20.variavel` foi mantido para preservar a identidade de instalação nas atualizações.

As telas web usam apenas a navbar do Rails: a barra de título adicional do Hotwire foi removida. O botão Voltar do Android continua disponível. O contêiner respeita barra de status, recortes de tela, navegação do sistema e teclado. Não há barra inferior de atalhos nesta versão; os menus existentes continuam seguindo as permissões do usuário.

## Compilar no WSL

Requisitos: JDK 17, Android SDK para Linux, Platform 35 e Build Tools 35.0.0. Configure `ANDROID_HOME` com o caminho do SDK (`~/Android/Sdk`), ou `sdk.dir` em `android/local.properties`. Não é necessário Android Studio ou emulador para compilar. O Heroku não precisa do SDK.

```bash
cd android
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

APK de teste: `app/build/outputs/apk/debug/app-debug.apk`.

A URL padrão fica em `gradle.properties`; `ANDROID_APP_URL` pode substituí-la e `-PappUrl=https://seu-dominio` tem prioridade sobre ambos. Nunca inclua credenciais na URL, pois ela fica embutida no APK.

Para atualizar o teste instalado, use um APK assinado com a mesma chave de debug. Com USB configurado, `adb install -r app/build/outputs/apk/debug/app-debug.apk` instala preservando os dados. Também é possível transferir e abrir o APK no celular.

## PDFs e downloads

- PDFs do sistema abrem no leitor interno com navegação por páginas, ampliação/redução, rolagem, salvar, compartilhar e imprimir. A impressão envia o documento completo ao serviço de impressão do Android. Busca textual e seleção de texto não estão implementadas.
- Excel, CSV, ZIP e demais respostas de download abrem uma tela com Salvar arquivo e Compartilhar. Há interceptação das rotas de exportação de checklist, documentos de invoices e blobs do Active Storage, inclusive URLs sem extensão.
- Salvar abre o seletor do Android para escolher pasta e nome. Não exige permissão de acesso amplo ao armazenamento.
- Compartilhar fornece uma cópia do arquivo com permissão temporária de leitura; não envia cookies nem a URL autenticada a outros aplicativos.
- A sessão Rails só acompanha requisições para a mesma origem HTTPS (host e porta). Redirecionamentos HTTPS externos não recebem esses cookies. Respostas HTML de login e erros HTTP são rejeitados.
- O limite é de 50 MB por arquivo. Downloads `blob:`/`data:` gerados apenas por JavaScript não são suportados; os relatórios do projeto usam endpoints HTTP.
- Arquivos de download e cópias compartilhadas ficam no cache privado. Cópias com mais de 24 horas são removidas na próxima inicialização do processo. PDFs de leitura e impressão são removidos ao encerrar seu fluxo normalmente. O Android também pode limpar o cache.
- Uma falha de carregamento de página oferece Tentar novamente; a conexão deve ser restabelecida antes. As telas de download e PDF também permitem repetir a tentativa.

## Notificações push (0.3.0)

O app está vinculado ao Firebase `workstation-7a115`, pacote `br.com.log20.variavel`. `app/google-services.json` é a configuração pública do cliente; nunca coloque a conta de serviço privada nessa pasta. Apenas o SDK Messaging foi adicionado; o SDK Analytics não foi incluído.

Após o login, Android 13+ solicita permissão. O celular registra o token FCM pelo WebView autenticado, usando o cookie e o CSRF do Rails. O usuário é definido pelo servidor, não por um parâmetro enviado pelo cliente. Novas visitas e retorno ao app sincronizam o token atual, inclusive após renovação. Se negar a permissão, é possível ativar depois nas configurações de notificações do Workstation no Android e reabrir o app.

O Rails envia push para os eventos já existentes no sino (tarefas, vencimentos, disponibilidade e atas). As mensagens mostram o título e o texto da notificação, com texto expandido e visibilidade privada na tela bloqueada; ao tocar, o servidor verifica a conta, marca a notificação como lida e abre seu destino. O Android descarta mensagens destinadas a outra conta. Logout desvincula os dispositivos registrados na mesma sessão sem afetar outros celulares. Tokens que o FCM informa como inválidos são removidos. Erros temporários são repetidos pelo job, sem registrar credenciais ou tokens nos logs.

No Heroku, configure `FIREBASE_SERVICE_ACCOUNT_JSON` com o JSON privado da conta de serviço e mantenha o worker Sidekiq ativo. O `release` do Procfile executa as migrações antes de ativar o deploy. A chave local fica em `~/.config/workstation/firebase-service-account.json`; não entra no APK nem no Git.

Validação: instale o APK novo, faça login, aceite notificações e atribua uma tarefa ao usuário a partir de outra conta. Teste com o app em segundo plano, toque no aviso e confira o destino. Depois faça logout e confirme que novos eventos não notificam esse aparelho. Não use somente o teste de mensagem do console para validar este fluxo: o Rails envia mensagens de dados com identificação do destinatário, enquanto o compositor do console utiliza mensagens de notificação.

O aparelho precisa de Google Play Services e conexão. A entrega depende do Android/FCM; forçar a parada do app nas configurações impede recebimento até abri-lo novamente. Não é necessário manter a tela do aplicativo aberta. Sem permissão, o sino dentro do site continua funcionando.

## Assinatura definitiva

O build `release` usa uma chave permanente, separada da chave de debug. A chave local está fora do repositório, em `~/.local/share/workstation-signing/workstation.p12`; a configuração privada fica em `android/keystore.properties`, ignorada pelo Git, com uma cópia em `~/.local/share/workstation-signing/keystore.properties`.

**Faça backup seguro dessa pasta. A chave e suas senhas são necessárias para futuras atualizações. Não as publique nem as envie para o Git.**

```bash
./gradlew :app:assembleRelease :app:lintRelease
```

APK assinado: `app/build/outputs/apk/release/app-release.apk`.

A passagem de debug para release exige desinstalar o debug, pois as assinaturas são diferentes. Isso remove a sessão e os dados locais, mas não os dados no Heroku. Depois da primeira instalação de release, mantenha a mesma chave e aumente `versionCode` em cada atualização. Para o teste atual, prefira o APK debug para atualizar a instalação existente.

Em outra máquina, restaure a chave e crie `android/keystore.properties` com `storeFile` (caminho absoluto), `storePassword`, `keyAlias` e `keyPassword`. Alternativamente, use as variáveis `WORKSTATION_KEYSTORE_PATH`, `WORKSTATION_STORE_PASSWORD`, `WORKSTATION_KEY_ALIAS` e `WORKSTATION_KEY_PASSWORD`. Um build de distribuição sem configuração de assinatura falha com instrução explícita.

## GitHub Actions

O workflow manual **Gerar APK Workstation** oferece `debug` e `release` e recebe a URL HTTPS. Executa build, testes de download/roteamento e lint; guarda o APK por 14 dias. Não publica o app nem faz deploy do Rails.

Para release, configure os secrets `WORKSTATION_KEYSTORE_BASE64` (conteúdo da chave em base64), `WORKSTATION_STORE_PASSWORD`, `WORKSTATION_KEY_ALIAS` e `WORKSTATION_KEY_PASSWORD`. Use a mesma chave local para manter a continuidade das atualizações. Essas credenciais não são incluídas no repositório. Debug em runners diferentes pode usar chaves diferentes.

A execução no GitHub ainda depende de publicar estes arquivos e configurar os secrets; a validação local não é uma execução de Actions.

## Verificação no celular

O usuário já validou os fluxos web principais e o leitor inicial de PDFs. Para esta versão, conferir:

1. Atualização sobre o debug anterior e manutenção de login.
2. Nome Workstation e ícone na tela inicial.
3. PDF: páginas, ampliação, salvar e abrir a cópia salva, compartilhar, impressão, rotação e Voltar.
4. XLSX, CSV, ZIP e anexo protegido: salvar, compartilhar, cancelar o seletor e tentar de novo.
5. Negar acesso ou usar sessão expirada: mensagem de erro, sem salvar HTML como documento.
6. Perda de conexão seguida de Tentar novamente após reconectar.
7. Login/logout e Voltar, câmera, galeria e áudio como regressão.

Testes locais cobrem autenticação, redirecionamentos, tipos de resposta e seleção das rotas. Não substituem o teste do seletor, compartilhamento e impressão no aparelho. Os avisos de versões mais novas de SDK/dependências são avaliados separadamente; não houve migração ampla dessas versões neste ajuste.
