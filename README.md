# AddKo

AddKo é uma plataforma Flutter para executar addons legados do Kodi e, futuramente, um novo modelo de App Plugin em Python.

## Objetivo da linha 0.1.x

A prioridade é compatibilidade com addons Kodi existentes sem exigir alteração do addon:

- instalar addons por ZIP;
- ler `addon.xml`;
- abrir rotas `plugin://`;
- executar o entrypoint Python do addon;
- suportar dependências `script.module.*` e repositórios Kodi;
- preservar organização e metadados dos repositórios;
- suportar `xbmc`, `xbmcaddon`, `xbmcplugin`, `xbmcgui` e `xbmcvfs`;
- evoluir para GUI legada, InputStream, PVR, VFS e demais addons binários.

## Regra da compatibilidade Kodi

O AddKo não deve inventar uma segunda API Kodi em Dart. O código oficial **Kodi Omega** é a fonte de verdade para nomes, assinaturas, constantes e contratos da API legada.

A referência está fixada no commit Kodi Omega:

`f8815ee40f49a700c047982d752be4b2a61420e2`

Arquivos SWIG oficiais necessários para os módulos Python estão preservados em `third_party/kodi_omega/`. O script `tools/vendor_kodi_omega_api.py` baixa um snapshot reproduzível dos headers legados quando precisamos atualizar a compatibilidade.

## Arquitetura

```text
Flutter UI
├── Launcher
├── Loja
└── Configurações
        │
        ▼
Addon Core
├── Addon Manager
├── Repository Manager
└── Dependency Resolver
        │
        ▼
AddKo Legacy Host
├── CPython Android
├── Kodi API bridge
│   ├── xbmc
│   ├── xbmcaddon
│   ├── xbmcgui
│   ├── xbmcplugin
│   └── xbmcvfs
├── Player / JSON-RPC / VFS bridge
└── Binary Addon ABI (em evolução)
```

Funções críticas continuam com implementação explícita no host. APIs auxiliares ainda não mapeadas passam pelo fallback genérico `kodi_proxy.py`, evitando que um addon morra imediatamente com `AttributeError` enquanto a ponte nativa é ampliada.

O objetivo final é manter Flutter como frontend e concentrar a compatibilidade Kodi no host/runtime, em vez de reproduzir o comportamento do Kodi widget por widget em Dart.

## Licença do código Kodi reutilizado

Kodi é GPL-2.0-or-later. Arquivos copiados do Kodi permanecem identificados e separados em `third_party/kodi_omega/`, com aviso de licença e commit de origem.

## Build Android local

Use `BUILD_ANDROID.bat`. O build executa smoke tests da camada Kodi/Python, valida o CPython Android e gera o APK ARM64 em:

`dist\AddKo-arm64-debug.apk`

## Estado

Projeto em desenvolvimento. A branch `main` é a linha principal.
