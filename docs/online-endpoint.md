# Servidor online (futuro Railway) — onde fica o endereço

Estado atual: **nenhum servidor online implantado**. Sem URL configurada, o
botão JOGAR ONLINE mostra "Servidor online ainda não configurado" e não
tenta conectar. O modo online não deve ser anunciado como funcional antes de
um servidor Railway real ser implantado e testado.

## Onde o jogo lê a URL

Um único lugar: `client/online_endpoint.gd` (`OnlineEndpoint.resolve`). A
primeira fonte não vazia vence:

1. argumento `--online-url=wss://...` (desenvolvimento e testes);
2. variável de ambiente `ARMED_MYSTERY_ONLINE_URL` (desktop; não existe na Web);
3. configuração do projeto `armed_mystery/network/online_url`:
   - vazia em `project.godot`;
   - numa build exportada, pode ser definida sem recompilar com um arquivo
     `override.cfg` ao lado do executável:

     ```ini
     [armed_mystery]
     network/online_url="wss://SEU-SERVICO.up.railway.app"
     ```

Para publicar a URL do Railway numa build oficial, prefira a opção 3
(`project.godot` ou `override.cfg`). Nenhuma tela conhece a URL.

## Formatos aceitos

- `ws://127.0.0.1:PORTA` e `ws://IP-DA-REDE:PORTA` (teste local ou LAN);
- `wss://dominio.up.railway.app` (produção; porta padrão 443).

Recusados, com mensagem em português e sem tentativa de conexão:
- esquema diferente de `ws://`/`wss://`;
- credencial (`usuario@`), consulta (`?`), fragmento (`#`) ou espaço;
- porta fora de 1–65535 e host inválido.

Numa build exportada de release, `ws://` para host que não é local (loopback
ou faixa privada) é bloqueado (`insecure`): em produção, use `wss://`.

Nunca coloque token, senha ou segredo na URL nem no `override.cfg`. O jogo
não tem contas, autenticação, matchmaking nem pagamento nesta fase.

## Testes

- `tests/menu_test.gd`: regras de URL; online sem URL; URL por argumento e
  por `ProjectSettings` (endpoint trocado sem mudar código).
- `tests/menu_flow_test.sh`, cenários `online-unconfigured` (nenhuma
  conexão) e `online-configured` (conecta no endereço passado por argumento).
