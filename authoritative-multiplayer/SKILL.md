---
name: authoritative-multiplayer
description: Projetar, implementar ou revisar sincronização multiplayer e regras autoritativas deste jogo Godot.
---

# Multiplayer autoritativo

Trate todo cliente como não confiável. O cliente envia intenção com identificador e dados mínimos; o servidor resolve a ação a partir do estado oficial. Valide jogador, fase da rodada, posse, munição, cadência, posição plausível, alcance e alvo. Envie papéis, créditos e compras secretas apenas ao dono. Mantenha a regra de transporte atrás de uma interface: WebSocket/TCP no Railway e ENet/UDP como opção futura. Teste duplicação, reordenação, spam e desconexão.

