# CORREDOR — Godot Version

1v1 Tower Siege Card Game reimplemented in **Godot 4.3**.

## Setup

1. Abre este diretório no **Godot 4.3 Editor**
2. O projeto carrega automaticamente
3. Clica **Run** (F5) para jogar

## Estrutura

- `scripts/` — GDScript (GameEngine, UIController)
- `scenes/` — Godot scenes (.tscn)
- `resources/` — cartas.json com 127 unidades + 300 táticos
- `assets/` — Imagens de cartas (cartas-3d/, apoios-3d/, taticos-3d/)

## Status

✅ GameEngine traduzido para GDScript
✅ 300 cartas táticas + dados
✅ UIController base
🔲 Visual do tabuleiro
🔲 Combate animado

## Motor

Lógica completa de:
- Dois baralhos (militar + tático)
- 6 tipos de cartas táticas (Equipamento, Magia, Consumível, Construção, Clima, Bênção)
- Torre por jogador (30 HP)
- Sistema de Pressão/Ruptura
- 127 cartas com habilidades

Tudo testado e funcional em JavaScript — aqui simplesmente traduzido para GDScript.
