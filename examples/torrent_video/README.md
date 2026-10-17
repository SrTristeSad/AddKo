# Vídeo por Torrent — primeiro addon modelo do AddKo

Este exemplo demonstra um miniapp Lua que abre vídeos por torrent através do [Luelement](https://github.com/SrTristeSad/Luelement), **sem incorporar BitTorrent ao núcleo AddKo**.

## Requisitos

1. AddKo em Android ARM64.
2. Plugin `Luelement.addko` instalado, com ID `io.addko.luelement`.
3. Android: app auxiliar Luelement Engine instalado; veja o repositório Luelement e seu smoke test Android.
4. Magnet ou arquivo .torrent de conteúdo que você está autorizado a acessar.

## Construir e instalar

Na raiz do projeto, execute `BUILD_EXEMPLO_TORRENT.bat` no Windows ou `python tools/build_torrent_video_example.py`.

O resultado será `dist/VideoTorrent-0.1.0.addko`. No AddKo, use **Loja → Instalar pacote**, selecione o arquivo e abra **Vídeo por Torrent**. O arquivo `.addko` não é um APK.

## Fluxo de reprodução

1. O addon consulta `addko.plugins.call('io.addko.luelement', 'health', {})` para mostrar o estado do motor.
2. O usuário cola um magnet ou URL de .torrent e toca em **Reproduzir**.
3. O addon chama `addko.plugins.call('io.addko.luelement', 'play', {uri = uri})`.
4. O Luelement conversa com o Elementum, realiza o buffering, obtém a URL HTTP local e abre o player do AddKo.
5. A lista de torrents já ativos é recuperada por `addko.plugins.call('io.addko.luelement', 'torrents', {})`; cada item pode ser aberto por `play` com `{id = id}`.

O addon não declara permissão de rede, mídia ou execução. Os recursos necessários são usados apenas pela dependência Luelement, dentro das permissões dela.

**Nota:** se houver vários vídeos no torrent, o Luelement pode pedir seleção. A preparação do stream pode demorar; o exemplo não inclui catálogos de filmes nem fontes de conteúdo.

## Testes

Execute `lua examples/torrent_video/tests/run.lua` na raiz do repositório. Os testes usam um Luelement simulado; **não** comprovam streaming real no telefone. A reprodução real exige um smoke test com o APK do Luelement Engine e um torrent de uso autorizado.
