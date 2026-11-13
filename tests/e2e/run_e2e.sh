#!/usr/bin/env bash
# testes de ponta a ponta, um fluxo por chamada:
#   solo       um contrato solo ate a segunda tentativa
#   coop-enet  partida em grupo pela rede local (ENet, UDP)
#   coop-ws    a mesma partida por WebSocket, o caminho do tunel Cloudflare
#   coop-relay a mesma partida pela sala online com codigo (relay/ rodando local)
# Sem argumento roda os quatro. PLAYERS escolhe o tamanho do grupo (padrao 4).
# O Godot pode sair com 0 mesmo com erro de script, entao o log tambem decide
set -u

GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "$0")/../.." && pwd)"
LOGS="${LOGS:-${TMPDIR:-/tmp}/the-last-contract-e2e}"
PLAYERS="${PLAYERS:-4}"
if [ "$PLAYERS" -lt 2 ] || [ "$PLAYERS" -gt 4 ]; then
	echo "PLAYERS precisa estar entre 2 e 4"
	exit 2
fi
mkdir -p "$LOGS"
failed=0

play() {
	"$GODOT" --headless --path "$PROJECT" "res://tests/e2e/$1" -- "${@:2}"
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

# os clientes so entram depois que o host abriu a porta; maquina de CI fria demora a carregar o jogo.
# Pela sala online o endereco e o codigo que o host recebe; "codigo" no lugar do endereco espera por ele
run_coop() {
	local flow=$1 host_arg=$2 address=$3 extra=${4:-} code i
	local ready="E2E host escutando"
	[ "$address" = "codigo" ] && ready="E2E sala "
	# shellcheck disable=SC2086
	play coop_e2e.tscn --role=host "$host_arg" $extra --adventurer=0 --autostart="$PLAYERS" --players="$PLAYERS" --name=Host > "$LOGS/$flow-host.log" 2>&1 &
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
		play coop_e2e.tscn --role=client --join="$address" $extra --adventurer="$i" --players="$PLAYERS" --name="Cliente$i" > "$LOGS/$flow-cliente$i.log" 2>&1 &
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

# a sala online roda local com o wrangler dev (relay/); precisa de Node e de npm ci em relay/
run_relay() {
	(cd "$PROJECT/relay" && npx wrangler dev --port 8787 --ip 127.0.0.1 --var SALAS_POR_IP_POR_MINUTO:100 --var MAX_SALAS:100) > "$LOGS/relay.log" 2>&1 &
	for _ in $(seq 90); do
		grep -q "Ready on" "$LOGS/relay.log" 2>/dev/null && break
		sleep 1
	done
	run_coop coop-relay --host=relay codigo --relay=ws://127.0.0.1:8787
	play recusa_e2e.tscn --join=ZZZZZZ --relay=ws://127.0.0.1:8787 > "$LOGS/recusa.log" 2>&1
	check_log recusa $?
	grep "sala-encerrada" "$LOGS/relay.log" || true
	pkill -f "wrangler dev" || true
	pkill -f workerd || true
}

case "${1:-todos}" in
	solo) run_solo ;;
	coop-enet) run_coop coop-enet --host 127.0.0.1 ;;
	coop-ws) run_coop coop-ws --host=ws ws://127.0.0.1:7777 ;;
	coop-relay) run_relay ;;
	todos)
		run_solo
		run_coop coop-enet --host 127.0.0.1
		run_coop coop-ws --host=ws ws://127.0.0.1:7777
		run_relay
		;;
	*)
		echo "uso: $0 [solo|coop-enet|coop-ws|coop-relay]"
		exit 2
		;;
esac
exit "$failed"
