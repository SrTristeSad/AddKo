# AddKo roadmap

## v0.1.x — Kodi Legacy Runtime

Objetivo: instalar um addon Kodi existente e executá-lo sem modificar o pacote.

### Fundação

- [x] shell Flutter e launcher em cards;
- [x] entrada para Loja;
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
- [ ] validação de checksum de repositório/pacote;
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
- [ ] CPython embarcado para Android/Android TV e demais plataformas sem Python do sistema;
- [ ] cobertura ampla de built-ins Kodi;
- [ ] JSON-RPC compatível;
- [ ] serviços `service.*` em segundo plano;
- [ ] scripts `xbmc.python.script` completos;
- [ ] `Window`, `WindowDialog`, `WindowXML` e controles Kodi traduzidos para Flutter;

### Mídia e addons binários

- [ ] Player Bridge;
- [ ] propriedades de `ListItem` para InputStream/DRM conectadas ao player;
- [ ] Kodi Binary Addon ABI host;
- [ ] InputStream ABI e `inputstream.adaptive`;
- [ ] InputStream FFmpeg Direct;
- [ ] PVR Binary ABI;
- [ ] Torrent Engine/bridge;
- [ ] VFS binário e demais famílias necessárias.

## Regra da Loja

O usuário registra a URL de um repositório. O AddKo aceita um descriptor `xbmc.addon.repository` ou um índice `addons.xml`/`addons.xml.gz`, sincroniza os metadados, apresenta os addons pelas categorias Kodi e usa o mesmo Addon Manager para baixar o pacote e resolver dependências automaticamente.

Dependências como `script.module.*`, `inputstream.*` e outros addons não aparecem como cards comuns no launcher apenas por estarem instaladas. O launcher é voltado aos addons executáveis pelo usuário.

## Plugin v2

Fica fora do escopo desta primeira etapa. O desenho futuro prevê App Plugins Python com recursos próprios, incluindo login, armazenamento, banco de dados, rede, serviços em segundo plano e APIs modernas do AddKo.
