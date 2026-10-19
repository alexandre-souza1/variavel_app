# Marca Logia

## Ícone do aplicativo

Fonte vetorial: `app/assets/images/launcher-icon.svg`, redesenhada a partir do
símbolo existente, com azul, azul-marinho e verde, sem textura rasterizada.
O desenho Android usa canvas de 108 × 108 e mantém o símbolo dentro da área
central de 66 × 66, com fundo branco separado, para evitar cortes no launcher.
Referência: [ícones adaptativos do Android](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive).

Execute `python3 bin/generate_app_icons` na raiz (requer `python3-gi`,
`gir1.2-rsvg-2.0` e ImageMagick) para regenerar o
drawable vetorial Android, PNGs web e ícones Apple. O manifesto web oferece
versões `any` e `maskable` separadas, com margem própria para cada uso.
O SVG usa o recorte de 72 × 72 para os ícones comuns; a versão `maskable`
usa o canvas completo de 108 × 108.

## Nome e palavra da marca

Nome exibido: **Logia**, com L maiúsculo e as demais letras minúsculas, sem espaço.

Imagem aplicada na barra: `app/assets/images/logo-logia-texto.png`.
Imagem de referência: `app/assets/images/logo-log-ia-texto.png`.
Gerada com a ferramenta integrada `image_gen`, em modo de edição, com fundo transparente.
Na barra, o filtro de cor existente mantém a palavra branca.

## Prompt utilizado

> Edit this existing app wordmark image. Change ONLY the lettering from 'Log IA' / 'LogIA' to exactly 'Logia' (capital L, lowercase o g i a), one continuous word with normal tight letter spacing, no space between g and i. Preserve the existing heavy geometric rounded sans-serif font style, clean professional brand lettering, proportions, thickness, smooth crisp edges, and transparent background. Preserve dark navy for 'Log' and bright blue for the final lowercase 'ia'. Do not add an icon, truck, symbols, slogan, border, shadow or background. Output just the word Logia as a clean horizontal wordmark, tightly framed like the reference, ideally matching the source 512 by 160 pixel proportions with a small amount of transparent padding so no glyph is cropped. The new lowercase i must have its dot, and lowercase a should match the geometric font style. This image will replace the wordmark in an app navbar. Exact spelling: L-o-g-i-a.

Verificado na barra em larguras de 1366, 390 e 320 px. Os nomes no manifesto web,
títulos, textos, notificações e recursos do Android também usam Logia. O nome do
aplicativo instalado no Android é atualizado com a instalação do próximo APK.
