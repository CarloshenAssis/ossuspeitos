# Armed Mystery

Primeiro marco do protótipo: um servidor Godot 4 headless autoritativo e clientes
locais conectados por WebSocket. Este marco cobre apenas conexão, apresentação e
lista pública; ainda não há gameplay.

## Requisitos

- Godot 4.4 ou mais recente (`godot4` ou `godot` no `PATH`).
- Bash para executar o teste de integração.

## Execução local

Inicie o servidor (por padrão, somente em `127.0.0.1:9080`):

```bash
godot4 --headless --path . -- --mode=server
```

Em quatro terminais, varie o identificador do cliente:

```bash
godot4 --headless --path . -- --mode=client --client-id=client-1
```

O endereço pode ser alterado com `--url=ws://host:porta`. O servidor aceita
`--bind=endereço`, `--port=porta` e também a variável de ambiente `PORT`.

## Teste servidor + quatro clientes

```bash
./tests/network_smoke_test.sh
```

O teste abre uma porta local aleatória, inicia cinco processos headless, exige
quatro sessões simultâneas com IDs de peer distintos e encerra todos os processos.
Se o executável não estiver no `PATH`, use
`GODOT_BIN=/caminho/para/godot ./tests/network_smoke_test.sh`.

Não há configuração nem deploy do Railway neste marco.
