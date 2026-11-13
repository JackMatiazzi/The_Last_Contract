#!/usr/bin/env bash
# testes de ponta a ponta, um fluxo por chamada:
#   solo       um contrato solo ate a segunda tentativa
#   coop-enet  partida em grupo pela rede local (ENet, UDP)
#   coop-ws    a mesma partida por WebSocket, o caminho do tunel Cloudflare
# Sem argumento roda os tres. PLAYERS escolhe o tamanho do grupo (padrao 4).
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

# os clientes so entram depois que o host abriu a porta; maquina de CI fria demora a carregar o jogo
run_coop() {
	local flow=$1 host_arg=$2 address=$3 code i
	play coop_e2e.tscn --role=host "$host_arg" --adventurer=0 --autostart="$PLAYERS" --players="$PLAYERS" --name=Host > "$LOGS/$flow-host.log" 2>&1 &
	local host_pid=$!
	for _ in $(seq 120); do
		grep -q "E2E host escutando" "$LOGS/$flow-host.log" 2>/dev/null && break
		kill -0 "$host_pid" 2>/dev/null || break
		sleep 0.5
	done
	local pids=()
	for i in $(seq 1 $((PLAYERS - 1))); do
		play coop_e2e.tscn --role=client --join="$address" --adventurer="$i" --players="$PLAYERS" --name="Cliente$i" > "$LOGS/$flow-cliente$i.log" 2>&1 &
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

case "${1:-todos}" in
	solo) run_solo ;;
	coop-enet) run_coop coop-enet --host 127.0.0.1 ;;
	coop-ws) run_coop coop-ws --host=ws ws://127.0.0.1:7777 ;;
	todos)
		run_solo
		run_coop coop-enet --host 127.0.0.1
		run_coop coop-ws --host=ws ws://127.0.0.1:7777
		;;
	*)
		echo "uso: $0 [solo|coop-enet|coop-ws]"
		exit 2
		;;
esac
exit "$failed"
