# Vídeo por Torrent — addon de diagnóstico do AddKo (v0.1.1)

Este miniapp Lua usa o serviço público do [Luelement](https://github.com/SrTristeSad/Luelement) para reproduzir vídeos por torrent. O addon não implementa BitTorrent e não solicita permissões de rede, mídia ou execução próprias.

## Requisitos atualizados — 17/10/2026

1. **AddKo Android ARM64 completo**, com o motor Elementum aprovado incluído no próprio APK assinado. A build leve sem Elementum não serve para o teste.
2. **Luelement 0.2.1-dev**, instalado como addon de serviço (`io.addko.luelement`). Ele fica em **Configurações → Gerenciar addons**, não aparece no launcher e inicia sob demanda.
3. **Vídeo por Torrent 0.1.1**, instalado como addon comum, declarando dependência de Luelement.
4. Conexão e espaço para buffering. Utilize apenas conteúdo que você esteja autorizado a acessar.

**Não instale um APK auxiliar do Luelement Engine.** A arquitetura atual já contém o provedor Elementum no APK completo do AddKo.

## Magnet de teste incluído

O campo de texto vem preenchido com o magnet fornecido pelo usuário, com a sintaxe corrigida:

```text
magnet:?xt=urn:btih:AJKRETO5SBORCFLSLNVJMZF2XNSTJC3N&tr=udp%3A%2F%2Ftracker.openbittorrent.com%3A80%2Fannounce&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce&tr=udp%3A%2F%2Ftracker.internetwarriors.net%3A1337%2Fannounce
```

Infohash: `AJKRETO5SBORCFLSLNVJMZF2XNSTJC3N` (Base32, 32 caracteres).

Os endereços UDP dos três trackers foram normalizados. Não verificamos a disponibilidade dos trackers, peers/seeds nem a identidade ou licença do conteúdo do torrent. Um hash válido **não** significa que o vídeo estará disponível.

O addon **não conecta ao torrent automaticamente** na abertura. O botão **Testar este magnet** inicia a solicitação de reprodução via Luelement somente por ação do usuário. Também é possível substituir o conteúdo do campo por outro magnet ou URL HTTP(S) para um arquivo `.torrent` e tocar em **Reproduzir**.

## Gerar o pacote instalável

No Windows, a partir da raiz do AddKo, execute `BUILD_EXEMPLO_TORRENT.bat`. Alternativamente, use `python tools/build_torrent_video_example.py`. O arquivo produzido será `dist/VideoTorrent-0.1.1.addko`.

## Procedimento de teste Android

1. Instale a build completa do AddKo (Android ARM64, com libelementum nativo).
2. Instale `Luelement-0.2.1-dev.addko` e autorize suas permissões, inclusive `native_engine` para o módulo `elementum`.
3. Instale `VideoTorrent-0.1.1.addko` pela Loja → Instalar pacote.
4. Abra **Vídeo por Torrent** e observe o status do motor. O serviço Luelement inicia na primeira chamada.
5. Toque em **Testar este magnet** e observe busca de metadados, buffering e reprodução, se houver peers.
6. Consulte **Torrents no Luelement** e, em caso de erro, anote a mensagem do aplicativo e os logs Android.

## Serviço consumido

```lua
addko.plugins.call("io.addko.luelement", "health", {})
addko.plugins.call("io.addko.luelement", "torrents", {})
addko.plugins.call("io.addko.luelement", "play", { uri = magnet })
```

O serviço conversa com o Elementum em `127.0.0.1:65220`, obtém o URL local de streaming e abre o player do AddKo. O consumidor não precisa implementar o protocolo BitTorrent.

## Testes

`lua examples/torrent_video/tests/run.lua` testa o frontend e o contrato do consumidor com serviço simulado, incluindo a tentativa explícita de abrir o magnet informado. Os testes do AddKo e do Luelement na CI também verificam seus contratos de integração. **A disponibilidade do torrent e a reprodução real ainda precisam de teste no Android físico.**
