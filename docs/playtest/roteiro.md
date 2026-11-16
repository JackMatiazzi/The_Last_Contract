# Roteiro de playtest

Sessão de 20 minutos por colega: 2 de preparo, 12 jogando, 6 de questionário.

## Antes

- Build da última release, aberta no menu principal.
- Controle Xbox conectado e teclado com mouse disponíveis; o colega escolhe.
- Telemetria ligada (vem ligada na build). O arquivo de cada partida fica em
  `%APPDATA%\Godot\app_userdata\The Last Contract\playtest\`.
- Um de nós joga de observador com a folha de observação abaixo. Não explicamos os controles
  nem ajudamos, a não ser que o colega fique travado por mais de 1 minuto.

Fala de abertura, igual para todos:

> Você foi contratado para limpar uma vila tomada por mortos-vivos. Joga do jeito que achar melhor
> e vai falando em voz alta o que está pensando. Não tem resposta certa: a gente está testando o
> jogo, não você.

## Tarefas

| # | Tarefa | Deu certo quando | Observar |
|---|---|---|---|
| 1 | Começar um contrato solo | assinou o contrato e entrou na fase | achou o botão Jogar? entendeu a assinatura? |
| 2 | Escolher um aventureiro | escolheu sem ajuda | por que escolheu esse? leu as habilidades? |
| 3 | Derrotar o primeiro grupo | o grupo da entrada caiu | descobriu o golpe pesado? usou a habilidade? |
| 4 | Usar uma poção | bebeu uma poção | achou o item na roda? entendeu o segurar? |
| 5 | Morrer e voltar | escolheu uma bênção e começou a tentativa II | entendeu que os inimigos também ficam mais fortes? |
| 6 | Achar o Necromante | o boss apareceu na praça | se perdeu? usou os pips de objetivo do HUD? |
| 7 | (opcional) Achar uma trava do calabouço | abriu atalho ou sala secreta | percebeu que a trava depende da classe? |

## Folha de observação

Uma linha por colega. O tempo e as mortes também saem na telemetria, então anote aqui o que o
arquivo não registra: onde travou, o que disse e o que fez de surpresa.

| Colega | Classe | Tarefas cumpridas | Onde travou | Frases marcantes | Bugs vistos |
|---|---|---|---|---|---|
| | | | | | |

## Depois

1. Questionário em [questionario.md](questionario.md), respondido sem a gente olhando.
2. Copiar o arquivo `.json` da partida para `docs/playtest/resultados/<nome-do-colega>.json`.
3. Bug visto vira issue no GitHub com o rótulo `playtest`, o passo a passo e a classe usada.

## Como ler os resultados

- Tarefa que menos da metade dos colegas cumpriu sem ajuda é problema de design, não de jogador.
- Comparar o tempo até o primeiro grupo e as mortes por tentativa entre as classes: se uma classe
  morre muito mais, é balanceamento.
- Nota de 1 a 5 abaixo de 3 em qualquer pergunta do questionário entra na lista de ajustes.
