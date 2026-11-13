# Co-op online

O lobby tem três jeitos de hospedar:

| Modo | Quando usar | Quem entra digita |
|---|---|---|
| Rede local | todos no mesmo Wi-Fi ou cabo | o IP do host |
| Sala online com código | redes diferentes ou rede que só libera HTTPS (faculdade); qualquer PC pode hospedar | o código de 6 letras |
| Túnel próprio | sem a sala online, com o `cloudflared` instalado no PC do host | o link `https://...trycloudflare.com` |

## Sala online

A sala online e o banco (consumo, telemetria do playtest e placar) são a API do jogo, num repositório
separado: [the-last-contract-api](https://github.com/JackMatiazzi/the-last-contract-api). Rotas, limites,
dados pessoais e deploy estão no README dela. Do lado do jogo:

- `scripts/network/relay_peer.gd` conversa com a sala e junta os pacotes em lotes de 100 ms;
- `scripts/autoload/net.gd` tem o endereço publicado em `RELAY_URL` e manda o relatório do fim da partida
  (`send_match_report`);
- o lobby avisa que o apelido aparece no placar público e fica guardado por 90 dias.

## Testar com a sala local

Com a API clonada ao lado do jogo (`../the-last-contract-api`, com `npm ci` feito):

```bash
bash tests/e2e/run_e2e.sh coop-relay
```

O jogo também entra numa sala local com `--relay=ws://127.0.0.1:8787`. A partida de carga
(`tests/e2e/carga_e2e.tscn`, com `--minutos=N`) põe 4 bots jogando pela sala para medir o custo. Medido em
13/11/2026 na vila: 45 minutos gastaram 1.971 requisições (39.412 mensagens). Os 2 primeiros minutos, com
todo mundo correndo, gastam o dobro do ritmo médio.
