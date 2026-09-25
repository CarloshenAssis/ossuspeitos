# Servidor online (Railway) — onde fica o endereço

Padrão do projeto: `wss://ossuspeitos-production.up.railway.app` (Railway).
Desde a fase 9 o servidor fala o protocolo 11 (salas privadas); builds do
protocolo 10 recebem a recusa de versão e precisam ser trocadas.

- Validado em 24/09/2026 por um cliente Godot real a partir do GitHub
  Actions (workflow `Online server probe`): TLS, WebSocket, handshake do
  protocolo 10, entrada na sala, snapshots e estado público da rodada.
- Ainda falta uma partida completa com jogadores humanos pela internet.
- O botão JOGAR ONLINE conecta nesse endereço e abre o LOBBY ONLINE: criar
  sala (recebe um código de 6 caracteres) ou entrar com o código de um
  amigo. A partida começa quando todos na sala marcam PRONTO (mínimo 4).
- CRIAR PARTIDA LOCAL e ENTRAR EM PARTIDA LAN não mudam.

## Onde o jogo lê a URL

Um único lugar: `client/online_endpoint.gd` (`OnlineEndpoint.resolve`). A
primeira fonte não vazia vence:

1. argumento `--online-url=wss://...` (desenvolvimento e testes);
2. variável de ambiente `ARMED_MYSTERY_ONLINE_URL` (desktop; não existe na Web);
3. configuração do projeto `armed_mystery/network/online_url`:
   - em `project.godot`: `wss://ossuspeitos-production.up.railway.app`;
   - numa build exportada, pode ser definida sem recompilar com um arquivo
     `override.cfg` ao lado do executável:

     ```ini
     [armed_mystery]
     network/online_url="wss://SEU-SERVICO.up.railway.app"
     ```

Para publicar a URL do Railway numa build oficial, prefira a opção 3
(`project.godot` ou `override.cfg`). Nenhuma tela conhece a URL.

Desligar o online numa execução (testes, evento só na LAN): o valor `off`,
por argumento (`--online-url=off`) ou pela variável de ambiente. Ele vence o
padrão do projeto e mostra "Modo online desligado nesta execução".

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

## Servidor (fase 8)

- **Imagem e configuração do Railway:** `docs/railway-deployment.md`.
- **Verificação:** depois de um domínio real validado, confira com a sonda
  (um cliente Godot real) antes de distribuir uma build apontando para ele:

  ```
  godot --headless --path . -- --mode=client --probe=true --url=wss://DOMINIO
  ```

  Critério de sucesso: `PROBE_OK result=joined ... snapshots=N round_state=... room=lobby`
  (criou uma sala própria, recebeu tráfego de jogo e saiu; a sala vazia é
  destruída pelo servidor em 30 s) ou `result=refused detail=...` com
  `room_full`, `round_in_progress`, `name_taken` ou `server_full` (o servidor
  fala o protocolo). O workflow `Online server
  probe` faz isso sob demanda (Actions → Run workflow) a partir de uma rede
  aberta.
