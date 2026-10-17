# AddKo Beta 0.3 — gerenciamento de addons

A tela inicial continua minimalista. O gerenciamento fica em **Configurações → Gerenciar addons**.

O usuário pode consultar ID, versão, permissões reais do manifesto instalado, dependências declaradas e outros addons que dependem do pacote. A consulta por atualizações usa **somente os repositórios já cadastrados**; versões mais novas são identificadas por SemVer, mas nunca são instaladas automaticamente. O botão de atualização abre a Loja.

## Desinstalação

1. Abra **Configurações → Gerenciar addons**, selecione o addon e escolha **Desinstalar**.
2. Confirme a operação. A opção **Apagar também os dados do addon** vem **desmarcada**.
3. Antes de remover, o AddKo verifica se outro addon instalado depende dele. Dependências bloqueiam a exclusão.
4. A sessão Lua é encerrada. O diretório instalado é movido para quarentena oculta e excluído.
5. Caso o usuário marque a limpeza, o diretório privado de dados também é colocado em quarentena e excluído.

A limpeza dos dados pode ser irreversível. Se falhar após começar, o aplicativo não informa que os dados foram apagados com sucesso. Diretórios simbólicos usados como raiz dos dados são rejeitados.

O fluxo preserva a home original: os controles administrativos aparecem apenas nas Configurações.