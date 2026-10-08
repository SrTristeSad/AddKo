# AddKo roadmap

## v0.1.x — Kodi Legacy Runtime

Objetivo: instalar um addon Kodi existente e executá-lo sem modificar o pacote.

### Fundação

- [x] shell Flutter e launcher em cards;
- [x] acesso visual à Loja no dock inferior do launcher;
- [x] dock inferior com ações visuais de Sair, Loja e Configurações;
- [x] cadastro e persistência de URL de repositório;
- [x] parser de `addon.xml`;
- [x] parser de descritor `xbmc.addon.repository`;
- [x] parser de URI `plugin://`;
- [x] sincronização HTTP de `addons.xml` / `addons.xml.gz`;
- [x] organização da Loja por tipos de addon Kodi;
- [x] instalador seguro de pacotes ZIP com staging/rollback;
- [x] validação do ID e versão do pacote contra o índice do repositório;
- [x] registro e descoberta de addons instalados;
- [x] resolvedor recursivo de dependências e versões;
- [x] instalação automática de dependências antes do addon principal;
- [x] atualização/reinstalação de pacote pela Loja;
- [x] desinstalação no Addon Manager (UI de gerenciamento ainda pendente);
- [x] validação de checksum de índices de repositório (MD5/SHA-1/SHA-256, incluindo endpoints GZip);
- [ ] checksum de pacote quando a origem fornecer digest verificável;
- [ ] cache local dos índices sincronizados;

### Runtime legado Python

- [x] worker Python isolado por invocação em processo no desktop;
- [x] `sys.argv` no formato esperado por plugins `plugin://`;
- [x] carregamento de `script.module.*` no `PYTHONPATH`;
- [x] bridge JSON entre Python e Flutter;
- [x] navegação de diretórios retornados por `xbmcplugin`;
- [x] `xbmcaddon` inicial, incluindo informações e settings persistentes;
- [x] `xbmcplugin` inicial, incluindo `addDirectoryItem`, `addDirectoryItems`, `endOfDirectory` e `setResolvedUrl`;
- [x] `xbmcvfs` inicial e tradução de `special://`;
- [x] `xbmc` inicial (`log`, built-ins, `Player`, `Monitor` e superfícies básicas);
- [x] `xbmcdrm` com superfície de compatibilidade para imports;
- [x] `xbmcgui.ListItem`, InfoTags, Dialog, Keyboard e Progress iniciais;
- [x] bridge bidirecional para `Dialog.ok`, `yesno`, `select`, `contextmenu`, `input`, `textviewer` e `Keyboard` usando Flutter;
- [x] `Window`, `WindowDialog` e modelo inicial de `WindowXML`/controles traduzidos para Flutter;
- [x] callbacks básicos de `WindowXML` trafegando pelo bridge Python ↔ Flutter;
- [x] JSON-RPC inicial (`JSONRPC.Ping`, `JSONRPC.Version`, propriedades básicas de Application/GUI e superfícies vazias seguras para Player/Files);
- [x] built-ins de navegação e execução: `RunPlugin`, `RunAddon`, `RunScript`, `Container.Update`, `Container.Refresh`, `PlayMedia`, `ActivateWindow`, `Addon.OpenSettings` e `Notification`;
- [x] built-ins ligados à Loja/Add-on Manager: `InstallAddon`, `UpdateAddonRepos` e `UpdateLocalAddons`;
- [x] `InstallAddon` procura o pacote nos repositórios ativos e usa o resolvedor recursivo de dependências do AddKo;
- [x] reconhecimento de `xbmc.service` e seu entrypoint em `addon.xml`;
- [x] supervisor de serviços Python em processos de segundo plano;
- [x] `xbmc.Monitor.abortRequested()` e `waitForAbort()` conectados ao supervisor para encerramento limpo;
- [x] serviços instalados/inseridos ou atualizados são reconciliados automaticamente pelo supervisor;
- [x] JSON-RPC de serviços é respondido pela mesma camada de compatibilidade do runtime legado;
- [x] eventos de `xbmc.service` podem ser encaminhados ao host global do AddKo;
- [x] notificações, `Player.play`, `InstallAddon`, `UpdateAddonRepos`, `UpdateLocalAddons` e `PlayMedia` diretos emitidos por serviços chegam aos controllers/UI globais;
- [x] painel em Configurações para listar serviços rodando, parados ou com falha;
- [x] reinício manual de serviços pelo painel;
- [x] `RunPlugin`, `RunAddon`, `RunScript`, `PlayMedia(plugin://...)` e `Container.Update(plugin://...)` disparados por serviços executam pelo runtime global;
- [x] resultados `setResolvedUrl` e built-ins produzidos por plugins/scripts chamados em background continuam sendo processados;
- [x] player ativo registra uma ponte global para receber `play`, `pause`, `stop`, `seekTime` e troca de mídia sem abrir outra instância;
- [ ] suportar os demais comandos do player (`playnext`, `playprevious`, legendas e playlists) no host global;
- [ ] `ActivateWindow` e navegação visual disparados por serviços;
- [ ] registrar histórico/log recente por serviço no painel;
- [ ] CPython embarcado para Android/Android TV e demais plataformas sem Python do sistema;
- [ ] ampliar os built-ins restantes do Kodi conforme addons reais exigirem;
- [ ] ampliar JSON-RPC para Addons, Files, Player, Playlist, Settings e bibliotecas;
- [ ] ampliar suporte a scripts Python e demais extension points usados por addons reais;
- [ ] ampliar `WindowXML` para mais tipos de controle, navegação/foco e recursos de skin.

### Mídia e addons binários

- [x] Player Bridge inicial usando `media_kit`;
- [x] reprodução direta de mídia resolvida por addons legados;
- [x] tradução inicial de propriedades de `ListItem` para headers, MIME, legendas e metadados InputStream/DRM;
- [ ] encaminhar propriedades InputStream/DRM para um host binário compatível;
- [ ] Kodi Binary Addon ABI host;
- [ ] InputStream ABI e `inputstream.adaptive`;
- [ ] InputStream FFmpeg Direct;
- [ ] PVR Binary ABI;
- [ ] Torrent Engine/bridge;
- [ ] VFS binário e demais famílias necessárias.

## Regra da Loja

O usuário registra a URL de um repositório. O AddKo aceita um descriptor `xbmc.addon.repository` ou um índice `addons.xml`/`addons.xml.gz`, sincroniza os metadados, apresenta os addons pelas categorias Kodi e usa o mesmo Addon Manager para baixar o pacote e resolver dependências automaticamente.

Dependências como `script.module.*`, `inputstream.*` e outros addons não aparecem como cards comuns no launcher apenas por estarem instaladas. O launcher é voltado aos addons executáveis pelo usuário.

A Loja também é o backend dos built-ins legados de instalação. Quando um addon antigo chama `InstallAddon`, `UpdateAddonRepos` ou `UpdateLocalAddons`, o AddKo encaminha a ação para os mesmos controllers usados pela interface da Loja.

## Plugin v2

Fica fora do escopo desta primeira etapa. O desenho futuro prevê App Plugins Python com recursos próprios, incluindo login, armazenamento, banco de dados, rede, serviços em segundo plano e APIs modernas do AddKo.
