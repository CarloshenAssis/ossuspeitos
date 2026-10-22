# Fase2 — progresso

Base59926cb, branchcodex/gameplay-specs-09-16. PR30/31abertos; maindd15ff2 inalterada. Autonomia de execução explícita prevalece sobre gates de aprovação de skills.

- Referências: em pesquisa independente.
- Baseline: concluída em arquivo limpo59926cb: importação0erros,37/37GDScript e5/5harnesses (smoke4,combate4,salas,RTT200,integração96). Software p95 20.979ms; três avisosObjectDB preexistentes. Ver baseline.md.
- SPEC09: em implementação, TDD e integração.
- SPEC10–16: pendentes.

Ruling: usar física analítica limitada para bloqueadores competitivos e Physics/Jolt apenas no laboratório — preserva replay e geometria — custo: objetos não terão dinâmica rígida arbitrária.
Ruling: protocolo12 explícito para ações/snapshots de ambiente sem novos métodos RPC — impede cliente11 ignorar colisões — custo: builds11/12 precisam ser atualizadas juntas.
Ruling: não inventar sprint, poderes secretos ou NPCs — regras incompletas e escopo — custo: corrida real/habilidades futuras permanecem fora desta fase.
