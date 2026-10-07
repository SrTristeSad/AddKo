# AddKo roadmap

## v0.1.x — Kodi Legacy Runtime

Objetivo: instalar um addon Kodi existente e executá-lo sem modificar o pacote.

### Fundação já iniciada

- [x] shell Flutter e launcher em cards;
- [x] entrada para Loja;
- [x] cadastro de URL de repositório;
- [x] persistência de repositórios;
- [x] parser inicial de `addon.xml`;
- [x] parser de descritor `xbmc.addon.repository`;
- [x] parser de URI `plugin://`;
- [x] sincronização HTTP de `addons.xml` / `addons.xml.gz`;
- [x] organização da Loja por tipos de addon do índice Kodi;
- [ ] validação de checksum de repositório;
- [ ] cache local de índices sincronizados;
- [ ] instalador de ZIP;
- [ ] registro de addons instalados;
- [ ] resolvedor de dependências;
- [ ] atualização e desinstalação de addons;
- [ ] host CPython;
- [ ] `xbmcaddon`;
- [ ] `xbmcplugin`;
- [ ] `xbmcgui`;
- [ ] `xbmcvfs`;
- [ ] tradução de `WindowXML` para Flutter;
- [ ] player bridge;
- [ ] InputStream binary ABI;
- [ ] PVR binary ABI.

## Regra de compatibilidade da Loja

O usuário pode registrar uma URL de repositório. O AddKo aceita um descriptor de addon `xbmc.addon.repository` ou um índice `addons.xml`/`addons.xml.gz`, sincroniza os metadados e apresenta os addons por suas categorias Kodi. Dependências e pacotes ZIP serão resolvidos pelo mesmo Addon Manager quando o instalador estiver concluído.

## Plugin v2

Fica fora do escopo da primeira etapa. O desenho futuro prevê App Plugins Python com recursos próprios, como login, armazenamento, banco de dados, rede e serviços em segundo plano.
