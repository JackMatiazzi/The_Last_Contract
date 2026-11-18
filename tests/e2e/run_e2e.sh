#!/usr/bin/env bash
# testes de ponta a ponta, um fluxo por chamada:
#   solo       um contrato solo ate a segunda tentativa
#   alcapao    do chefe morto ao calabouco apertando E no alcapao
#   vida-extra ate a terceira tentativa, conferindo o dano recebido menor a cada 2 tentativas
#   coop-enet  partida em grupo pela rede local (ENet, UDP)
#   coop-ws    a mesma partida por WebSocket, o caminho do tunel Cloudflare
#   coop-relay a mesma partida pela sala online com codigo, com a API (the-last-contract-api) rodando local
#   partida    uma partida inteira simulada por bots pela sala online local: Pedra Alta, Necromante,
#              alcapao, Michio no grupo e calabouco (uns 8 minutos)
# Sem argumento roda todos. PLAYERS escolhe o tamanho do grupo (padrao 4). API_DIR aponta a copia da
# API, com npm ci feito; o padrao e a pasta ao lado do jogo. RELAY_PORT muda a porta da sala local (padrao 8787).
# HOST_DISPLAY="--position 640,1080 --resolution 1152x648" abre o host com janela (placa de video de verdade).
# O Godot pode sair com 0 mesmo com erro de script, entao o log tambem decide
set -u

GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "$0")/../.." && pwd)"
API_DIR="${API_DIR:-$PROJECT/../the-last-contract-api}"
LOGS="${LOGS:-${TMPDIR:-/tmp}/the-last-contract-e2e}"
PLAYERS="${PLAYERS:-4}"
if [ "$PLAYERS" -lt 2 ] || [ "$PLAYERS" -gt 4 ]; then
	echo "PLAYERS precisa estar entre 2 e 4"
	exit 2
fi
mkdir -p "$LOGS"
failed=0

# cada processo grava o próprio godot.log em $LOGS: os testes não empurram para fora os logs de quem joga
play() {
	# shellcheck disable=SC2086
	"$GODOT" ${E2E_DISPLAY:---headless} --path "$PROJECT" --log-file "$LOGS/godot-${1%.tscn}-$RANDOM$RANDOM.log" "res://tests/e2e/$1" -- "${@:2}"
}

check_log() {
	local log="$LOGS/$1.log"
	grep -E "E2E" "$log"
	if [ "$2" -ne 0 ] || grep -q "SCRIPT ERROR" "$log" || ! grep -q "E2E OK" "$log"; then
		echo "== $1 falhou (codigo $2); erros do log:"
		grep -E "SCRIPT ERROR|ERROR:|E2E FALHOU" "$log" | head -20
		failed=1
	fi
}

run_solo() {
	play solo_e2e.tscn > "$LOGS/solo.log" 2>&1
	check_log solo $?
}


run_alcapao() {
	play alcapao_e2e.tscn > "$LOGS/alcapao.log" 2>&1
	check_log alcapao $?
}

run_vida_extra() {
	play vida_extra_e2e.tscn > "$LOGS/vida-extra.log" 2>&1
	check_log vida-extra $?
}

# os clientes so entram depois que o host abriu a porta; maquina de CI fria demora a carregar o jogo.
# Pela sala online o endereco e o codigo que o host recebe; "codigo" no lugar do endereco espera por ele
run_coop() {
	local flow=$1 host_arg=$2 address=$3 extra=${4:-} code i
	local ready="E2E host escutando"
	[ "$address" = "codigo" ] && ready="E2E sala "
	# shellcheck disable=SC2086
	E2E_DISPLAY="${HOST_DISPLAY:---headless}" play "${COOP_SCENE:-coop_e2e.tscn}" --role=host "$host_arg" $extra --adventurer=0 --autostart="$PLAYERS" --players="$PLAYERS" --name=Host > "$LOGS/$flow-host.log" 2>&1 &
	local host_pid=$!
	for _ in $(seq 120); do
		grep -q "$ready" "$LOGS/$flow-host.log" 2>/dev/null && break
		kill -0 "$host_pid" 2>/dev/null || break
		sleep 0.5
	done
	if [ "$address" = "codigo" ]; then
		address=$(grep -oE "E2E sala [A-Z2-9]{6}" "$LOGS/$flow-host.log" | head -1 | cut -d' ' -f3)
	fi
	local pids=()
	for i in $(seq 1 $((PLAYERS - 1))); do
		# shellcheck disable=SC2086
		play "${COOP_SCENE:-coop_e2e.tscn}" --role=client --join="$address" $extra --adventurer="$i" --players="$PLAYERS" --name="Cliente$i" > "$LOGS/$flow-cliente$i.log" 2>&1 &
		pids+=($!)
	done
	for i in "${!pids[@]}"; do
		wait "${pids[$i]}"
		code=$?
		check_log "$flow-cliente$((i + 1))" "$code"
	done
	wait "$host_pid"
	code=$?
	check_log "$flow-host" "$code"
}

# a sala online roda local com o wrangler dev da API; precisa de Node e de npm ci em API_DIR
# a sala local precisa da API clonada ao lado do jogo (ou API_DIR=...), com npm ci feito
have_api() {
	if [ -f "$API_DIR/wrangler.toml" ]; then
		return 0
	fi
	echo "== $1 precisa da API em $API_DIR (ou API_DIR=...)"
	failed=1
	return 1
}

start_relay() {
	(cd "$API_DIR" && npx wrangler d1 migrations apply DB --local) > "$LOGS/relay-banco.log" 2>&1
	(cd "$API_DIR" && npx wrangler dev --port ${RELAY_PORT:-8787} --ip 127.0.0.1 --var SALAS_POR_IP_POR_MINUTO:100 --var MAX_SALAS:100 --var ADMIN_TOKEN:e2e-local) > "$LOGS/relay.log" 2>&1 &
	for _ in $(seq 90); do
		grep -q "Ready on" "$LOGS/relay.log" 2>/dev/null && break
		sleep 1
	done
}

run_partida() {
	if ! have_api partida; then
		return
	fi
	start_relay
	COOP_SCENE=partida_e2e.tscn run_coop partida --host=relay codigo --relay=ws://127.0.0.1:${RELAY_PORT:-8787}
	echo "linhas de rede dos jogadores:"
	grep -h "\[rede" "$LOGS"/partida-*.log || true
	echo "quedas na sala local:"
	grep -iE "4008|mensagens demais|limite|expir" "$LOGS/relay.log" || echo "nenhuma"
	pkill -f "wrangler dev" || true
	pkill -f workerd || true
}

run_relay() {
	if ! have_api coop-relay; then
		return
	fi
	start_relay
	run_coop coop-relay --host=relay codigo --relay=ws://127.0.0.1:${RELAY_PORT:-8787}
	play recusa_e2e.tscn --join=ZZZZZZ --relay=ws://127.0.0.1:${RELAY_PORT:-8787} > "$LOGS/recusa.log" 2>&1
	check_log recusa $?
	echo "consumo do dia na sala local:"
	node -e "fetch('http://127.0.0.1:${RELAY_PORT:-8787}/uso', { headers: { Authorization: 'Bearer e2e-local' } }).then((r) => r.text()).then(console.log)" || true
	pkill -f "wrangler dev" || true
	pkill -f workerd || true
}

case "${1:-todos}" in
	solo) run_solo ;;
	alcapao) run_alcapao ;;
	vida-extra) run_vida_extra ;;
	coop-enet) run_coop coop-enet --host 127.0.0.1 ;;
	coop-ws) run_coop coop-ws --host=ws ws://127.0.0.1:7777 ;;
	coop-relay) run_relay ;;
	partida) run_partida ;;
	todos)
		run_solo
		run_alcapao
		run_vida_extra
		run_coop coop-enet --host 127.0.0.1
		run_coop coop-ws --host=ws ws://127.0.0.1:7777
		run_relay
		;;
	*)
		echo "uso: $0 [solo|alcapao|vida-extra|coop-enet|coop-ws|coop-relay|partida]"
		exit 2
		;;
esac
exit "$failed"
