# AddKo

AddKo é uma plataforma Flutter focada em executar addons legados do Kodi e, futuramente, um novo modelo de App Plugin em Python.

## Objetivo da v0.1.0

A primeira etapa é compatibilidade com addons Kodi existentes, sem exigir alteração do addon:

- instalar addons por ZIP;
- ler `addon.xml`;
- abrir rotas `plugin://`;
- executar o entrypoint Python do addon;
- suportar dependências entre addons (`script.module.*`, `inputstream.*`, etc.);
- oferecer uma Loja baseada em repositórios adicionados pelo usuário;
- preservar a organização e os metadados fornecidos por cada repositório;
- implementar gradualmente as APIs `xbmc`, `xbmcaddon`, `xbmcplugin`, `xbmcgui` e `xbmcvfs`;
- suportar GUI legada e, mais adiante, addons binários como InputStream e PVR.

## Arquitetura inicial

```text
Flutter App
├── Launcher de plugins
├── Loja
└── Configurações
        │
        ▼
Addon Core
├── Addon Manager
├── Repository Manager
├── Dependency Resolver
└── plugin:// Router
        │
        ▼
Kodi Compatibility Runtime
├── Python Host
├── xbmc*
├── GUI bridge
└── Binary Addon bridge (futuro)
```

## Estado

Projeto em desenvolvimento inicial. A branch `main` é a linha principal de desenvolvimento.
