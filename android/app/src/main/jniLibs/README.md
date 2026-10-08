# CPython Android runtime

Esta pasta receberá as bibliotecas CPython por ABI usadas pelo host nativo do AddKo.

Estrutura esperada:

```text
jniLibs/
├── arm64-v8a/
│   └── libpython3.13.so
├── armeabi-v7a/
│   └── libpython3.13.so
└── x86_64/
    └── libpython3.13.so
```

O host `libaddko_python_host.so` procura `libpython3.13.so`, `libpython3.12.so`, `libpython3.11.so` e `libpython3.so`, nessa ordem.

Além da biblioteca compartilhada, o pacote final precisará incluir a stdlib Python correspondente. As bibliotecas CPython ainda não são versionadas no repositório nesta etapa; o loader e a integração Android já estão preparados para recebê-las.
