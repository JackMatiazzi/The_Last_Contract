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

### Deploy (uma vez, por quem tem a conta Cloudflare)

```bash
cd relay
npm ci
npx wrangler login
npm run deploy
```

O deploy mostra o endereço `https://the-last-contract-relay.<conta>.workers.dev`. Troque o `https`
por `wss` e coloque em `RELAY_URL`, no `scripts/autoload/net.gd`. Para conferir: abrir
`https://the-last-contract-relay.<conta>.workers.dev/saude` no navegador responde `ok`.

### Custo

O plano gratuito dá 100 mil requisições por dia (zera às 21h de Brasília). Cada 20 mensagens que
chegam na sala contam como 1 requisição; o que sai não conta. O jogo junta os pacotes e manda no
máximo 10 mensagens por segundo por jogador, e personagem parado não manda nada. Uma partida de
50 minutos com 4 jogadores fica abaixo de 6 mil requisições. Ao fechar, cada sala escreve no log do
Worker quantas mensagens e requisições gastou (`npx wrangler tail`).

### Rodar e testar local

```bash
cd relay
npm test
npx wrangler dev --port 8787
```

O jogo usa a sala local com `--relay=ws://127.0.0.1:8787`. O teste ponta a ponta com 4 jogadores
pela sala é `bash tests/e2e/run_e2e.sh coop-relay`.
