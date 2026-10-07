# AddKo roadmap

## v0.1.x — Kodi Legacy Runtime

Objetivo: instalar um addon Kodi existente e executá-lo sem modificar o pacote.

### Fundação já iniciada

- [x] shell Flutter e launcher em cards;
- [x] entrada para Loja;
- [x] cadastro básico de URL de repositório;
- [x] parser inicial de `addon.xml`;
- [x] parser de descritor `xbmc.addon.repository`;
- [x] parser de URI `plugin://`;
- [ ] persistência de repositórios;
- [ ] sincronização de `addons.xml` / `addons.xml.gz`;
- [ ] instalador de ZIP;
- [ ] registro de addons instalados;
- [ ] resolvedor de dependências;
- [ ] host CPython;
- [ ] `xbmcaddon`;
- [ ] `xbmcplugin`;
- [ ] `xbmcgui`;
- [ ] `xbmcvfs`;
- [ ] tradução de `WindowXML` para Flutter;
- [ ] player bridge;
- [ ] InputStream binary ABI;
- [ ] PVR binary ABI.

## Plugin v2

Fica fora do escopo da primeira etapa. O desenho futuro prevê App Plugins Python com recursos próprios, como login, armazenamento, banco de dados, rede e serviços em segundo plano.
