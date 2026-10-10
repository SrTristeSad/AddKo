# Matriz de compatibilidade Kodi 21 (Omega)

O alvo do AddKo é **compatibilidade com add-ons do Kodi 21 (Omega)**, não copiar
ou embutir o aplicativo Kodi inteiro. A referência fica fixada no commit
`f8815ee40f49a700c047982d752be4b2a61420e2` do repositório oficial do Kodi.

Legenda:

- ✅ funcional no fluxo principal do AddKo;
- 🟡 parcial: API existe, mas ainda há comportamento do Kodi a implementar;
- 🧱 planejado/nativo: exige um subsistema nativo equivalente ao Kodi;
- ➖ fora do objetivo atual do launcher, salvo se um add-on depender disso.

## API Python oficial

| Superfície | Estado | Observação |
| --- | --- | --- |
| `xbmc` | 🟡 | Player, Monitor, built-ins, JSON-RPC e várias consultas existem; a superfície rara cai no proxy de compatibilidade. |
| `xbmcaddon` | ✅/🟡 | Informações, localização e settings tipados funcionam; diferenças raras de schema/UI ainda podem existir. |
| `xbmcgui` | 🟡 | Dialog, ListItem, Window e WindowXML possuem bridge; o skin/GUI engine completo do Kodi não é embutido. |
| `xbmcplugin` | ✅/🟡 | Diretórios, resolução de URL, sort/content/category/fanart/properties e semântica de `endOfDirectory` estão cobertos. |
| `xbmcvfs` | 🟡 | Arquivos locais e `special://` funcionam; protocolos VFS fornecidos por add-ons binários dependem do host VFS nativo. |
| `xbmcdrm` | 🟡 | Superfície Kodi Omega completa e assinaturas corretas; operações criptográficas reais ainda precisam de MediaDrm/host nativo. |
| `xbmcwsgi` | 🟡 | Objetos WSGI oficiais existem para import/compatibilidade; o servidor HTTP/WSGI interno do Kodi ainda não é hospedado. |

O fallback `kodi_proxy.py` evita quebra de import por símbolos acessórios ainda não
promovidos a implementação dedicada. Ele **não conta como implementação funcional**
de uma API: chamadas importantes devem ganhar bridge real.

## Execução de add-ons

| Recurso | Estado | Observação |
| --- | --- | --- |
| `addon.xml` / dependências | ✅ | Parser preserva extensões arbitrárias e resolve dependências obrigatórias. |
| `xbmc.python.pluginsource` | ✅ | `plugin://`, handle, query, listagens e resolução de mídia. |
| `xbmc.python.script` | ✅/🟡 | Execução e argumentos disponíveis; ampliar semântica de todos os tipos script-like continua em auditoria. |
| `xbmc.python.module` | ✅ | Dependências entram no `sys.path` recursivamente. |
| `xbmc.service` | ✅/🟡 | Supervisor, abort/wait, restart e eventos; lifecycle raro do Kodi pode exigir ajustes. |
| weather/subtitles/lyrics/library | 🟡 | O parser reconhece os extension points; ainda faltam hosts específicos equivalentes aos subsistemas Kodi que os invocam. |
| `xbmc.webinterface` / WSGI | 🧱 | API Python WSGI existe; falta o servidor web e o invoker HTTP. |
| repositórios | ✅/🟡 | Índices, ZIP, checksums, `.gz`, dependências, update e repositórios instaláveis. |
| `special://` | 🟡 | Home/profile/userdata/temp principais; ampliar aliases e semântica conforme testes reais. |
| banco de add-ons | 🟡 | `Addons33.db` compatível com consultas legadas comuns; não é uma cópia integral de todos os bancos do Kodi. |
| `reuselanguageinvoker` | 🧱 | Ainda falta manter uma sessão/subinterpretador persistente por add-on. |

## Player e mídia

| Recurso | Estado | Observação |
| --- | --- | --- |
| URLs HTTP/HTTPS/arquivo | ✅/🟡 | Player global e bridge de controle existem. |
| propriedades de `ListItem` | ✅/🟡 | Caminho, headers e metadados principais são transportados ao player. |
| legendas | 🟡 | APIs básicas existem; compatibilidade completa depende do player/formatos. |
| HLS/DASH simples | 🟡 | Depende do backend de mídia e da origem. |
| DRM por propriedades do item | 🟡 | Metadados chegam ao host; ampliar integração nativa de licença/Widevine. |
| `inputstream.adaptive` | 🧱 | Principal próximo alvo do host binário Kodi. |

## ABI de add-ons binários Kodi Omega

As versões declaradas em `KodiHostCapabilities` seguem `kodi/versions.h` da
referência Omega. Declarar a capacidade permite resolver corretamente o grafo de
dependências, mas **não significa que a instância binária já seja executável**.

| ABI | Versão Omega | Host funcional |
| --- | ---: | --- |
| `kodi.binary.instance.audiodecoder` | 4.0.0 | 🧱 |
| `kodi.binary.instance.audioencoder` | 3.0.0 | 🧱 |
| `kodi.binary.instance.game` | 3.0.2 | 🧱 |
| `kodi.binary.instance.imagedecoder` | 3.0.1 | 🧱 |
| `kodi.binary.instance.inputstream` | 3.3.0 | 🧱 prioridade máxima |
| `kodi.binary.instance.peripheral` | 3.0.2 | 🧱 |
| `kodi.binary.instance.pvr` | 8.3.0 | 🧱 |
| `kodi.binary.instance.screensaver` | 2.2.0 | 🧱 |
| `kodi.binary.instance.vfs` | 3.0.1 | 🧱 |
| `kodi.binary.instance.visualization` | 4.0.0 | 🧱 |
| `kodi.binary.instance.videocodec` | 2.1.0 | 🧱 |

Também estão declaradas as APIs globais `main`, `general`, `gui`, `audioengine`,
`filesystem`, `network` e `tools` com as versões exatas do Omega.

## O que não deve ser chamado de “100% Kodi” ainda

O Kodi completo contém subsistemas que vão além do contrato de add-ons: skin
engine, biblioteca de mídia e scanners, PVR frontend, game frontend, servidor
web/UPnP, periféricos, AudioEngine, VideoPlayer/demuxers, VFS binário, gerência de
instâncias C/C++, bancos internos e serviços do core. Reproduzir tudo isso seria
praticamente construir um segundo Kodi.

Para o objetivo do AddKo, a métrica correta é: **um add-on legado deve conseguir
instalar dependências, importar as APIs esperadas, navegar, abrir seus diálogos e
resolver/reproduzir mídia sem precisar saber que não está dentro do Kodi**.

## Verificação automática

Execute:

```bash
python tools/audit_kodi_omega_compat.py
python tools/test_kodi_shims.py
```

A primeira verificação impede regressões estruturais contra a referência Omega;
a segunda executa smoke tests das APIs Python. Nenhuma delas substitui testes de
add-ons reais no Android/Android TV.
