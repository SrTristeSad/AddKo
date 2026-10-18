# Motores nativos aprovados — AddKo Android

Esta integração preserva o formato **.addko somente Lua**. Um addon não recebe autorização para abrir arquivos executáveis ou carregar bibliotecas `.so` arbitrárias.

O AddKo oferece a API genérica `addko.engines` com os métodos `available(id)`, `start(id)`, `status(id)` e `stop(id)`. Para utilizar um motor, o manifesto precisa declarar a permissão genérica `native_engine` e listar `native_engines`, por exemplo `["elementum"]`. A escolha aparece no diálogo de instalação.

Na build Android ARM64 completa, um provedor aprovado Elementum é empacotado como bibliotecas nativas dentro do **próprio APK assinado do AddKo**; o serviço é executado em processo Android separado, com `android:exported=false` e `foregroundServiceType=dataSync`. A build baixa `libelementum.so` e `libc++_shared.so` do commit fixado do projeto upstream e confere o tamanho e SHA-1 de objeto Git antes de incorporá-las. A versão de distribuição leve pode ser compilada com `-PaddkoIncludeElementum=false` sem o motor.

O addon Luelement continua independente e chama o provedor `elementum` por meio do registro genérico, sem APK auxiliar. Outros addons precisam declarar `io.addko.luelement` como dependência para chamar seu serviço `health/play`.

**Limites de segurança:** o processo separado previne que um crash de JNI derrube diretamente o processo Flutter, mas não é uma sandbox com UID diferente. Somente código nativo validado, revisado e incluído no APK pode executar. O uso de foreground service de sincronização de dados está sujeito a limites do Android 15; a configuração não deve ser apresentada como serviço ilimitado.

**Testes ainda necessários:** instalar em Android ARM64, abrir Luelement, validar a disponibilidade do motor assinado, RPC 65221, HTTP 65220, magnet legal, buffering, redirecionamento, player e seek. Validar também encerramento, reconexão, 6h de dataSync no Android 15 e uso de bateria.

## Serviços e consumidores

O manifesto Lua opcional `"type": "service"` informa ao AddKo que a ferramenta oferece funcionalidades para outros addons, e não uma tela para o usuário abrir. Ela **não aparece na home**; continua disponível em Configurações → Gerenciar addons, com atualização, permissões e bloqueio de desinstalação enquanto outros addons dependem dela. Manifestos antigos sem esse campo continuam como `"app"`.

Exemplo consumidor:

```json
{"id":"io.example.videos","name":"Meu Vídeo","version":"1.0.0","entry":"main.lua","permissions":[],"dependencies":["io.addko.luelement"]}
```

```lua
local ready = addko.plugins.call("io.addko.luelement", "health", {})
local url = addko.plugins.call("io.addko.luelement", "stream", {uri = magnet})
-- O addon consumidor decide como apresentar e reproduzir o conteúdo.
```

O AddKo inicializa o serviço sob demanda, na primeira chamada; não inicializa motores apenas por estarem instalados.
