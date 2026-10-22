# Fase2 — progresso

Base59926cb, branchcodex/gameplay-specs-09-16. PR30/31abertos; maindd15ff2 inalterada. Autonomia de execução explícita prevalece sobre gates de aprovação de skills.

- Referências: oito projetos pesquisados independentemente, SHAs/licenças/versões em references.md. Nenhum código/asset externo importado. DialogueManager atual4.6+ e Terrain3D atual4.5 não atendem4.4.1; candidatas antigas documentadas sem instalação.
- Baseline: concluída em arquivo limpo59926cb: importação0erros,37/37GDScript e5/5harnesses (smoke4,combate4,salas,RTT200,integração96). Software p95 20.979ms; três avisosObjectDB preexistentes. Ver baseline.md.
- SPEC09: implementado e validado inicialmente:43checks, movement/netcode266/combat86 e smoke4. Laboratório nativoGodotPhysics e Jolt PASS; sem trocar backendprodução. CorreçãofimrodadacarregandoRED→GREEN. Ver09-physics.md. Integração09–16 completa ainda pendente.
- SPEC10: implementado/integradopor sala;39/39suítes incluindo30checksaudio e smoke4 PASS. Occlusãoexperimental desligada; corrida nãoinventada. Ver10-audio.md.
- SPEC11–16: pendentes.

Ruling: usar física analítica limitada para bloqueadores competitivos e Physics/Jolt apenas no laboratório — preserva replay e geometria — custo: objetos não terão dinâmica rígida arbitrária.
Ruling: protocolo12 explícito para ações/snapshots de ambiente sem novos métodos RPC — impede cliente11 ignorar colisões — custo: builds11/12 precisam ser atualizadas juntas.
Ruling: não inventar sprint, poderes secretos ou NPCs — regras incompletas e escopo — custo: corrida real/habilidades futuras permanecem fora desta fase.

Ruling: oclusão por AABB fica opcional/desabilitada por padrão — orçamento/escuta ainda não certificados — custo: sons de outra sala usam distância/posicionamento sem abafamento por parede no padrão.
