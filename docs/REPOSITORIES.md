# Repositórios AddKo — índice v1

A Loja da Beta 0.3 usa fontes **opt-in**: o usuário cadastra uma URL HTTPS de um arquivo JSON. Nenhum repositório é pré-configurado.

## Formato

Publique um arquivo como https://seudominio.com/addko/index.json:

~~~json
{
  "schema": 1,
  "name": "Minha comunidade",
  "addons": [
    {
      "id": "com.exemplo.app",
      "name": "Exemplo",
      "version": "1.0.0",
      "description": "Um mini-app Lua para o AddKo.",
      "category": "Jogos",
      "icon": "icons/exemplo.png",
      "icon_sha256": "SHA256_HEXADECIMAL_REAL_DO_ARQUIVO_DE_ICONE",
      "file": "packages/exemplo-1.0.0.addko",
      "sha256": "COLOQUE_AQUI_O_SHA256_HEXADECIMAL_DE_64_CARACTERES"
    }
  ]
}
~~~

Os valores SHA-256 acima são **ilustrativos e inválidos**. Calcule os hashes reais sobre **os bytes do pacote final e do ícone** e substitua pelos 64 caracteres hexadecimais correspondentes.

`category` é opcional (até 40 caracteres, padrão `Outros`). `icon` e `icon_sha256` são opcionais, mas precisam ser fornecidos **juntos**; são aceitos PNG, JPEG e WebP com até 256 KiB, sempre no mesmo host HTTPS da fonte. Sem ícone, a Loja mostra um pictograma genérico para a categoria. A versão instalada é obtida do app, não do catálogo.

O AddKo só sinaliza **Atualização disponível** se conseguir comparar versões compatíveis com SemVer e a publicada for maior. Versões iguais aparecem como instaladas; versões locais maiores não são marcadas como atualização; versões incompatíveis são exibidas como `Versão diferente`. A loja não atualiza sozinha.

O campo file é relativo à pasta do JSON. O pacote deve estar no **mesmo host e porta HTTPS do índice**, sem redirecionamentos. O índice aceita no máximo 256 addons; cada ID pode aparecer somente uma vez.

## Instalação

1. O usuário abre **Loja → Adicionar repositório** e informa a URL HTTPS do índice.
2. O AddKo valida a URL e a estrutura do índice, depois persiste a fonte no dispositivo.
3. O usuário escolhe um addon na Loja e toca em **Instalar**.
4. O AddKo baixa o pacote (até 16 MiB), verifica o SHA-256 e compara ID, nome e versão com o manifesto.
5. O usuário vê as permissões e dependências e confirma; o instalador existente valida o ZIP, faz staging e rollback se necessário.

Fontes indisponíveis continuam cadastradas, mas exibem erro na atualização. Remover uma fonte não remove addons já instalados. **Não há instalação ou atualização automática.**

## Segurança e limites

- Apenas índices HTTPS .json, sem credenciais, query ou fragmento.
- Rejeição de endereços locais/IPs literais; verificação DNS prévia; redirecionamentos desativados.
- Índices até 512 KiB; no máximo 40 repositórios e 256 addons por índice.
- Pacotes até 16 MiB; SHA-256 obrigatório; mesma origem HTTPS.
- Ícones até 256 KiB e SHA-256 obrigatório caso o campo `icon` esteja presente; carregados somente depois de verificados.
- SHA-256 protege contra divergência em relação ao índice recebido; não prova que o publicador é confiável.
- A verificação DNS anterior à conexão não elimina completamente DNS rebinding; o transporte deve ser reforçado em versão futura.
