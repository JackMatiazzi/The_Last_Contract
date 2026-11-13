# Co-op online

O lobby tem três jeitos de hospedar:

| Modo | Quando usar | Quem entra digita |
|---|---|---|
| Rede local | todos no mesmo Wi-Fi ou cabo | o IP do host |
| Sala online com código | redes diferentes ou rede que só libera HTTPS (faculdade); qualquer PC pode hospedar | o código de 6 letras |
| Túnel próprio | sem a sala online, com o `cloudflared` instalado no PC do host | o link `https://...trycloudflare.com` |

## Sala online (pasta `relay/`)

É um Worker do Cloudflare com um Durable Object por sala. A sala só entrega pacotes: carimba quem
mandou, aceita até 4 jogadores, tranca quando a partida começa e fecha depois de 10 minutos parada
ou 90 minutos aberta. Até 8 salas ao mesmo tempo.

### Banco (D1)

A pasta `relay/migrations/` cria três tabelas e uma view:
- `partidas`: o consumo de cada sala, usado no orçamento do dia;
- `fichas`: hash da ficha de uso único que cada jogador recebe ao entrar;
- `telemetria`: o relatório do fim da partida, com apelido, classe, resultado, tentativas, mortes e eventos;
- view `placar`: só apelido e números agregados.

Perto de 50 mil requisições no dia, a sala para de abrir salas novas até 21h (horário de Brasília).

O apelido é dado pessoal. O lobby avisa o jogador, e tudo some depois de 90 dias (`RETENCAO_DIAS`),
numa limpeza que roda uma vez por dia. Um pedido para apagar um apelido vai para
`DELETE /jogadores/APELIDO`, com o cabeçalho `Authorization: Bearer <ADMIN_TOKEN>`.

| Rota | O que faz |
|---|---|
| `GET /uso` | requisições e partidas de hoje (com o `ADMIN_TOKEN`) |
| `GET /placar` | os 20 melhores apelidos (cache de 5 minutos) |
| `POST /telemetria` | relatório do jogo: só com a ficha da partida, uma vez, de partida com 2 ou mais jogadores |

Proteções do orçamento:
- cada rede (IP, só em memória) gasta no máximo 15 mil requisições por dia;
- cada sala fecha em 100 mil mensagens;
- banco fora do ar não trava o co-op: a partida segue, só fica sem placar.

### Deploy (uma vez, por quem tem a conta Cloudflare)

```bash
cd relay
npm ci
npx wrangler login
npx wrangler d1 create the-last-contract
```

Copie o `database_id` que o comando mostrar para o `wrangler.toml` e continue:

```bash
npx wrangler d1 migrations apply DB --remote
npx wrangler secret put ADMIN_TOKEN
npm run deploy
```

O deploy mostra o endereço `https://the-last-contract-relay.<conta>.workers.dev`. Troque o `https`
por `wss` e coloque em `RELAY_URL`, no `scripts/autoload/net.gd`. Para conferir: abrir
`https://the-last-contract-relay.<conta>.workers.dev/saude` no navegador responde `ok`, e `/uso`
mostra o consumo do dia.

### Custo

O plano gratuito dá 100 mil requisições por dia (zera às 21h de Brasília). Cada 20 mensagens que
chegam na sala contam como 1 requisição; o que sai não conta. O jogo junta os pacotes e manda no
máximo 10 mensagens por segundo por jogador, e personagem parado não manda nada. Uma partida de
50 minutos com 4 jogadores fica abaixo de 6 mil requisições. Ao fechar, cada sala grava no banco
quantas mensagens e requisições gastou (`GET /uso`).

### Rodar e testar local

```bash
cd relay
npm test
npx wrangler dev --port 8787
```

O jogo usa a sala local com `--relay=ws://127.0.0.1:8787`. O teste ponta a ponta com 4 jogadores
pela sala é `bash tests/e2e/run_e2e.sh coop-relay`.

A partida de carga (`tests/e2e/carga_e2e.tscn`, com `--minutos=N`) põe 4 bots jogando pela sala local
para medir o custo. Medido em 13/11/2026 na vila: 45 minutos gastaram 1.971 requisições (39.412
mensagens); os 2 primeiros minutos, com todo mundo correndo, gastam o dobro do ritmo médio.
