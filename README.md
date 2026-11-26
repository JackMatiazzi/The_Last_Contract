# The Last Contract

Jogo de ação 3D em terceira pessoa feito em Godot 4.7 para a Avaliação Grau 2 de Programação de Jogos.

Uma vila medieval foi tomada por mortos-vivos e um Lorde contrata um aventureiro para limpá-la e
derrotar o Necromante. Cada tentativa tem uma vida só: ao morrer, você revive com uma bênção (que
os mortos-vivos também recebem) ou desiste e é executado.

**Autores:** André Bartzen Araujo, Jackson Matiazzi e José Maciel Camargo.

## Como jogar

| Ação | Teclado e mouse | Controle (Xbox) |
|---|---|---|
| Mover | W A S D | Analógico esquerdo |
| Correr | Segurar Espaço | Clicar no analógico esquerdo |
| Câmera | Mouse | Analógico direito |
| Atacar (segurar para o golpe pesado) | Botão esquerdo | RT |
| Habilidade secundária | Botão direito | LT |
| Trocar item | Roda do mouse para baixo | Direcional para baixo |
| Interagir (segurar para beber o item) | E | X |
| Placar | Segurar Tab | Segurar Back |
| Pausar | Esc | Start |

O Mage abre o Portal com a habilidade secundária.

Limpe os grupos de esqueletos da vila. Quando o último cair, o Necromante surge na praça.

## Como rodar

No Windows, extraia o ZIP e abra `TheLastContract.exe`. Em máquinas com vídeo integrado, troque
Configurações > Vídeo > Gráficos para Desempenho: o jogo reinicia no renderizador mais leve.

Abra o projeto no Godot 4.7.2 e rode a cena principal (F5). Para jogar em grupo, um jogador hospeda
pelo menu Co-op e os outros entram pelo endereço dele. Fora da rede local, dá para usar o Radmin VPN.

## Testes

Os testes usam o gdUnit4 e ficam em `tests/`. O GitHub Actions roda a suíte e um teste ponta a ponta
a cada push e pull request. Cada merge no `main` gera uma release com o jogo para Windows e Linux.

## Como trabalhamos

Cada tarefa vira uma branch a partir da `desenvolvimento` e volta por pull request, que só entra
com os testes passando. No fim da semana, a `desenvolvimento` vai para o `main`.

Usamos todos o Godot 4.7.2, porque outra versão regrava as cenas. Antes de mexer no mapa, no
personagem base ou no `project.godot`, a gente avisa no grupo para não dar conflito.

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `scenes/` | Cenas do jogo |
| `scripts/` | Scripts, na mesma organização de `scenes/` |
| `resources/` | Aventureiros, bênçãos, perfis de inimigo e sons |
| `assets/` | Modelos, áudio e fonte de terceiros |
| `tests/` | Testes |
| `docs/` | Documento do projeto e GDD, em LaTeX |

## Créditos (CC0, exceto a fonte)

- Modelos: [KayKit Adventurers](https://kaylousberg.itch.io/kaykit-adventurers), [KayKit Skeletons](https://kaylousberg.itch.io/kaykit-skeletons) e [KayKit Dungeon Pack](https://kaylousberg.itch.io/kaykit-dungeon-pack) (Kay Lousberg); [Medieval Village MegaKit](https://quaternius.itch.io/medieval-village-megakit) (Quaternius).
- Efeitos sonoros: [RPG Audio](https://kenney.nl/assets/rpg-audio), [Impact Sounds](https://kenney.nl/assets/impact-sounds) e [Interface Sounds](https://kenney.nl/assets/interface-sounds) (Kenney).
- Música: [Dark Cavern Ambient](https://opengameart.org/content/dark-cavern-ambient) (Paul Wortmann) e [Medieval fair [Loop]](https://opengameart.org/content/medieval-fair-loop) (Woli34).
- Fonte dos títulos: [Cinzel](https://github.com/NDISCOVER/Cinzel) (The Cinzel Project Authors), sob a [SIL Open Font License 1.1](assets/fonts/OFL.txt).

### Envio ao itch.io

O workflow **Publicar no itch.io** roda quando uma release é publicada pela equipe. Para enviar uma
entrega criada automaticamente pelo GitHub, rode o mesmo workflow na branch `main` em **Actions**.
O GitHub não dispara outro workflow para releases geradas pelo `GITHUB_TOKEN` da entrega automática.

- Configure o segredo `BUTLER_API_KEY` no repositório com a chave da conta que tem acesso ao projeto no itch.io.
- Depois do primeiro envio, marque o canal `web` como jogável no navegador. Os canais `windows` e `linux`
  são os downloads com co-op. Os envios seguintes atualizam as mesmas entradas.
- O envio confere se a API aceita telemetria do navegador antes de substituir as builds. A participação
  no playtest é opcional em **Configurações → Dados**.
