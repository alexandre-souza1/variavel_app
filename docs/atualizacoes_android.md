# Atualização do Log IA pelo aplicativo

A versão Android **0.4.0, código 8**, habilita o atualizador. É necessário instalar esse APK uma vez pelo método anterior e publicar as alterações do Rails. As versões seguintes podem ser recebidas pelo próprio app.

## Preparação

1. Publique o Rails com a migração `20261014130000_create_android_releases.rb`. O processo `release` do Heroku já executa as migrações. Localmente, use `bin/rails db:migrate`.
2. Mantenha o Active Storage configurado para armazenamento durável. A produção já utiliza Amazon S3; não armazene o APK no disco temporário do Heroku.
3. Instale o APK inicial com a assinatura correspondente à instalação existente: release sobre release, debug local sobre debug local. A troca de assinatura exige reinstalação e remove os dados locais.
4. Abra o menu do usuário como administrador e escolha **Atualizações do aplicativo** (`/admin/atualizacoes-android`). Publique o APK inicial para permitir seu download pelos usuários das versões anteriores.

## Disponibilizar uma nova versão

1. Aumente `versionCode` e ajuste `versionName` em `android/app/build.gradle.kts`. A próxima atualização após a inicial deve usar código **9 ou maior**.
2. Gere o APK com a mesma chave permanente: `cd android && ./gradlew :app:assembleRelease :app:testDebugUnitTest :app:lintRelease`. O workflow **Gerar APK Workstation** também gera o APK e inclui `output-metadata.json` no artefato, com a versão e o código que devem ser informados na publicação.
3. Na área **Atualizações do aplicativo**, selecione **Produção**, informe os valores do APK, anexe o arquivo assinado e descreva as mudanças. Toque em **Disponibilizar atualização**. APKs de teste devem ser publicados em **Teste (debug)** e assinados pela mesma chave de debug dos aparelhos usados no teste; runners diferentes podem gerar chaves diferentes.
4. O app oferece a versão disponível de maior código no canal correspondente. **Retirar** interrompe novas consultas/downloads pelo endpoint do aplicativo; não reverte instalações nem invalida um download ou link de armazenamento já obtido.

O APK é compilado no computador ou no GitHub Actions. O atualizador do celular consulta, baixa e inicia a instalação; não compila o projeto.

## Uso no celular

Após o login, o app verifica atualizações ao abrir/retomar as telas, no máximo a cada seis horas por usuário e versão instalada. Uma falha de conexão é ignorada no uso normal e pode ser tentada novamente após cinco minutos com o app aberto. Não há download automático nem verificação em segundo plano.

O aviso oferece **Atualizar** e **Agora não**. Também é possível consultar imediatamente pelo menu do usuário, em **Atualizar aplicativo**. Nessa tela, toque em **Atualizar** para baixar; após o download, toque em **Instalar atualização**. Se necessário, autorize o Log IA a instalar aplicativos na tela de configurações do Android e volte. O instalador do sistema pede a confirmação final. Cancelar permite tentar novamente.

Versões anteriores abrem uma página web de download ao tocar no menu. Alterações do Rails continuam chegando pelo servidor; recursos nativos precisam de APK novo.

## Verificações e limites

- Publicação e retirada exigem administrador. Consulta e download exigem login; o servidor separa os canais `release` e `debug`.
- O servidor aceita arquivos `.apk` de até 150 MB que contenham `AndroidManifest.xml`, calcula tamanho e SHA-256 e armazena o anexo pelo Active Storage. A versão informada é conferida no celular; o servidor não interpreta o manifesto binário nem verifica a assinatura do APK.
- O celular limita o download ao tamanho anunciado, verifica tamanho e SHA-256, lê o pacote e exige o identificador `br.com.log20.variavel`, o código e o nome anunciados, código maior que o instalado e exatamente os mesmos certificados de assinatura. Rotação de chave não é suportada por este atualizador.
- Requisições usam HTTPS. A consulta não segue redirecionamentos. O download pode seguir os redirecionamentos do Active Storage, com cookies Rails enviados exclusivamente à origem da aplicação.
- O APK fica no cache privado, compartilhado com o instalador por URI com permissão temporária de leitura. Cópias antigas são removidas na próxima inicialização após 24 horas; downloads interrompidos ou inválidos são descartados. A rotação da tela mantém o estado do download; após encerramento do processo, a tela consulta novamente.
- Este fluxo é para distribuição direta por APK. Uma eventual distribuição pela Google Play deve usar o fluxo de atualização da loja e rever a permissão `REQUEST_INSTALL_PACKAGES` conforme as políticas da Play.

## Validação

```bash
PARALLEL_WORKERS=1 bin/rails test test/models/android_release_test.rb test/controllers/admin/android_releases_controller_test.rb test/controllers/mobile/android_releases_controller_test.rb test/controllers/mobile/push_devices_controller_test.rb test/controllers/admin/ai_settings_controller_test.rb test/controllers/navigation_journeys_test.rb
cd android
./gradlew :app:assembleDebug :app:assembleRelease :app:testDebugUnitTest :app:lintDebug :app:lintRelease
```

No aparelho, instale a versão inicial e publique uma versão de código maior assinada com a mesma chave. Confira aviso, opção de adiar, consulta manual, download, rotação da tela, permissão, cancelamento, instalação e manutenção do login. Teste também sessão expirada, perda de conexão, APK com assinatura diferente e versão informada incorretamente. Os testes locais não substituem essa confirmação no celular.

Referências: [distribuição fora da loja](https://developer.android.com/distribute/marketing-tools/alternative-distribution), [requisitos das atualizações](https://developer.android.com/google/play/app-updates).
