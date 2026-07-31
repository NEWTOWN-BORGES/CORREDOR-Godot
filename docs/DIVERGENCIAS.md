# Bíblia vs. jogo — o que está alinhado e o que falta

Registo do estado do código face à **Game Design Bible v1.0** (31/07/2026) e
ao **TABULEIRO.pdf**. Actualizar quando algum destes pontos mudar.

## Alinhado

| Ponto da Bíblia | Onde está no código |
|---|---|
| Linha 1 com 6 casas, Linha 2 com 4 | `BoardGeometry` — retaguarda usa as colunas 1-4 |
| Torres como objectivo | `Game.TOWER_MAX = 30`, vitória por Torre a zero |
| Uma só mão visível, de Apoio | `players[x]["hand"]`, 5 cartas |
| Unidades chegam automaticamente | Sistema de reforços: 1 por turno, até 3 guardados |
| Sem custo, mana, energia ou ouro | `custo` não tem efeito nenhum em jogo |
| Sem matriz global de tipos | Removida. As vantagens vivem nas habilidades das cartas |
| Apoio = Equipamento, Magia, Consumível | `DeckManager.CATEGORIAS_APOIO` |
| Unidades fixas depois de colocadas | Não há movimento; só o Apoio AP-14 reposiciona |
| Tabuleiro em ruínas abaixo de 25% | `BoardRenderer.update_board_art()` |
| Baralhos e cemitério no tabuleiro | Pontas da retaguarda + zona central, como no PDF |

## Por fazer — faltam dados

**Espécie, Classe e Alcance.** A Bíblia (§21-23) exige estes campos na carta.
O `cartas.json` não tem nenhum, e a arte 750×1050 já está desenhada sem eles.
Não foram inventados. O Alcance é o único com efeito mecânico previsto
(unidades de alcance atacam da segunda linha) — hoje esse papel é feito pelo
campo `papel` (`ATIRADOR`).

**Anexo A — 15 cartas Reinos/Guerreiros.** São cartas diferentes das que estão
no `cartas.json` e não têm arte. A própria Bíblia avisa que foram escritas
antes de fechar as Core Rules.

**Anexo B — 30 cartas de Apoio.** O jogo tem 160 táticas por facção geradas
proceduralmente. A lista nominal da Bíblia (Espada Longa, Bola de Fogo, Poção
de Cura...) ainda não existe como dados.

## Divergências assumidas

**Raridades.** Os dados têm `COMUM, RARA, ÉPICA, LENDÁRIA, HERÓI`. A Bíblia
pede `COMUM, INCOMUM, RARA, ÉPICA, LENDÁRIA`. Falta `INCOMUM`, sobra `HERÓI`.
Corrigir obriga a remapear as 100 unidades e a arte mostra a moldura antiga.

**Alinhamentos.** O jogo tem ORDEM, PUREZA, SELVA, MAGIA, SOMBRA e coesão de
baralho. A Bíblia não os menciona — nem para os manter nem para os remover.
Ficam como estão até haver decisão.

**"Comuns não têm habilidade"** (§25). Por verificar contra os dados.

**Reserva de reforços.** A Bíblia (§16) diz que o jogador "recebe uma unidade
por turno e joga-a directamente", e marca mão/reserva como *por definir*. A
reserva de 3 é a concretização escolhida.

## O tabuleiro, zona a zona

Cores como no `TABULEIRO.pdf`, espelhadas entre os lados:

```
              [cemitério]              amarelo
   [militar]  4 casas  [apoio]         retaguarda IA
        6 casas linha 1                frente IA
        6 casas linha 1                frente jogador
   [apoio]  4 casas  [militar]         retaguarda jogador
              [cemitério]              amarelo
```

O cemitério junta as unidades mortas e os Apoios já gastos — é o
"baralho das cartas que morrem".
