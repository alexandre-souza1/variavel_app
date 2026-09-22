# Rotogramas

A página `/rotogramas` é pública, assim como Consultas e a Central de Padrões. Os atalhos de Consultas e AZ Consultas abrem o mesmo catálogo; `?origem=az` mantém o retorno para AZ Consultas.

## Conteúdo

- `config/rotogramas.json`: catálogo das 26 localidades, coordenadas, nomes alternativos, quantidade de páginas e tamanho do PDF.
- `public/rotogramas/<id>/documento.pdf`: PDF original, sem alterações.
- `public/rotogramas/<id>/previa.jpg`: prévia da primeira página.
- `public/rotogramas/<id>/pagina-NN.jpg`: todas as páginas renderizadas a 180 dpi, carregadas uma por vez pelo leitor.
- `public/rotogramas/rotograma-completo.pdf`: documento geral original.

Os arquivos foram copiados da pasta `ROTOGRAMA` fornecida pelo usuário. A aplicação não depende do Windows ou de acesso ao OneDrive. O conjunto ocupa aproximadamente 70 MB e deve acompanhar o deploy. Os arquivos em `public` são servidos pelo Rails na configuração de produção existente.

Favoritos e os últimos oito documentos abertos ficam no `localStorage` do navegador/aparelho. Se o armazenamento estiver indisponível, a página continua funcionando durante a sessão. Isso não baixa documentos para uso offline.

## Mapa

Leaflet 1.9.4 está incluído em `vendor/javascript/leaflet.js` e `vendor/assets/stylesheets/leaflet.css`, com a licença original em `vendor/javascript/leaflet.LICENSE`. Os mapas de fundo dependem de internet e usam tiles do OpenStreetMap com atribuição visível. Falhas no mapa não impedem a consulta pela lista. Os marcadores identificam localidades; os trajetos e orientações operacionais estão nos PDFs originais.

Referências:

- [Leaflet, documentação oficial](https://leafletjs.com/reference-1.9.4.html)
- [Política dos tiles do OpenStreetMap](https://operations.osmfoundation.org/policies/tiles/)
- [Coordenadas das sedes municipais](https://github.com/kelvins/municipios-brasileiros)
- [São Clemente, distrito de Santa Helena](https://mapcarta.com/24982472)
- [Novo Sarandi, distrito de Toledo](https://mapcarta.com/19257782)

O rótulo “Nova Sarandi” foi mantido conforme o arquivo original; a busca também aceita “Novo Sarandi”. As coordenadas indicam a localidade, não um ponto de entrega.

## Atualização dos documentos

Ao substituir um PDF, renderize novamente **todas** as páginas e atualize `pages` e `bytes` no catálogo. Não use apenas a primeira página: os arquivos originais têm de duas a quatro páginas.

Exemplo com Ghostscript e ImageMagick instalados, a partir da raiz do projeto:

```sh
gs -q -dNOPAUSE -dBATCH -sDEVICE=jpeg -dJPEGQ=85 -r180 \
  -sOutputFile=public/rotogramas/toledo/pagina-%02d.jpg \
  public/rotogramas/toledo/documento.pdf
convert public/rotogramas/toledo/pagina-01.jpg -resize 480x -quality 80 \
  public/rotogramas/toledo/previa.jpg
```

Remova páginas antigas excedentes se o novo documento tiver menos páginas. As ferramentas de conversão são necessárias somente para atualizar o conteúdo, não em runtime.

## Validação

```sh
bin/rails assets:precompile
bin/rails server -p 3100
BASE_URL=http://127.0.0.1:3100 node test/browser/rotogramas_test.cjs
BASE_URL=http://127.0.0.1:3100 node test/browser/rotogramas_navigation_test.cjs
```

O teste usa Playwright/Chromium e cobre desktop e viewport de iPhone: busca sem acentos, favoritos persistidos, recentes, seleção de cidade, navegação entre páginas, zoom, PDF original, visualização em lista, estado vazio e ausência de rolagem horizontal na página. Capturas são salvas em `tmp`.

O segundo teste cobre os atalhos nas duas telas, o retorno pelo Turbo, a seleção por marcador, o fechamento por Escape e a consulta sem tiles ou localStorage disponíveis.
