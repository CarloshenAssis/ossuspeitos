# Instalação do kit Astra + Codex

## 1. Coloque os arquivos no repositório

Extraia este pacote na raiz do novo repositório. Os diretórios `.codex` e `.agents` precisam permanecer versionados.

## 2. Confirme a estrutura

Devem existir:

- `AGENTS.md`
- `.codex/config.toml`
- `.codex/agents/*.toml`
- `.agents/skills/*/SKILL.md`

## 3. Abra o repositório no Codex

Inicie o Codex a partir da raiz Git e selecione GPT-6 Astra. O arquivo `.codex/config.toml` configura Astra também como modelo padrão dos subagentes.

As skills são descobertas automaticamente. Se não aparecerem, reinicie o Codex e confira com `/skills`.

## 4. Verifique os agentes

No Codex CLI, use `/agent` para inspecionar threads. Um teste inicial seguro é:

> Leia AGENTS.md. Peça ao architect para propor a estrutura mínima do protótipo, ao networking para revisar o transporte Railway e ao qa para criar critérios de aceitação. Espere todos e consolide um único plano; não escreva código ainda.

## 5. Crie a base Godot

Depois de aprovar o plano:

> Implemente o primeiro marco do projeto em Godot 4: servidor headless e quatro clientes locais conectando por WebSocket, sem gameplay. Use os agentes adequados, evite edições paralelas nos mesmos arquivos, execute o teste e documente como iniciar.

## 6. Railway

Somente quando o servidor local funcionar, peça:

> Prepare Dockerfile e configuração para Railway. Não execute deploy. Garanta WebSocket/TCP, porta por variável de ambiente, healthcheck e execução headless.

Após revisar os arquivos, conecte o repositório no painel Railway e autorize o deploy. O teste gratuito e os limites podem mudar; confira a página de preços antes de criar recursos.

## Observação

Custom agents de projeto ficam em `.codex/agents/`. Skills do repositório ficam em `.agents/skills/`. `AGENTS.md` contém regras sempre carregadas; skills devem conter fluxos específicos e curtos.

