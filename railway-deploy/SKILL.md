---
name: railway-deploy
description: Preparar ou revisar o deploy do servidor Godot headless deste projeto no Railway.
---

# Deploy Railway

Use um container reproduzível e um processo Godot headless. Exponha a partida por WebSocket/TCP; não presuma suporte público a ENet/UDP. Leia porta e demais opções de variáveis de ambiente. Inclua encerramento gracioso, logs essenciais e healthcheck apropriado. Mantenha o deploy substituível por VPS. Preparar arquivos é permitido quando solicitado; executar deploy, criar recursos ou gerar cobrança exige autorização explícita.

