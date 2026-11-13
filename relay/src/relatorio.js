// valida o relatorio que o jogo manda no fim da partida (POST /telemetria) antes de chegar no banco.
// Os eventos so passam com tipos e campos conhecidos: texto livre nao entra (pode ter dado pessoal)

export const BYTES_DO_CORPO = 20 * 1024;
const BYTES_DOS_EVENTOS = 16 * 1024;
const MAX_EVENTOS = 500;
const CLASSES = ["Knight", "Barbarian", "Mage", "Rogue"];
const RESULTADOS = ["victory", "executed", "contract_failed", "left_party", "back_to_menu"];
const TIPOS_DE_EVENTO = ["attempt_started", "player_died", "group_cleared", "boss_summoned", "blessing_chosen", ...RESULTADOS];
const INVISIVEIS = /[\p{C}\p{M}⠀ㅤﾠ]/gu;

// mesma regra para gravar e para apagar: NFC junta os acentos antes de tirar o que nao aparece
export function limparApelido(texto) {
	return String(texto ?? "").normalize("NFC").replace(INVISIVEIS, "").replace(/\s+/gu, " ").trim().slice(0, 16);
}

// "José" e "JOSÉ" sao o mesmo jogador no placar e no pedido de apagamento
export function chaveDoApelido(apelido) {
	return limparApelido(apelido).toLocaleLowerCase("pt-BR");
}

export function validarRelatorio(corpo) {
	if (typeof corpo !== "object" || corpo === null || !Array.isArray(corpo.eventos ?? [])) {
		return { erro: "relatorio invalido" };
	}
	const apelido = limparApelido(corpo.apelido);
	const eventos = (corpo.eventos ?? []).slice(0, MAX_EVENTOS).map(limparEvento).filter(Boolean);
	const dados = JSON.stringify(eventos);
	const numeros = {
		tentativas: Math.trunc(Number(corpo.tentativas)),
		mortes: Math.trunc(Number(corpo.mortes)),
		minutos: Math.round(Number(corpo.minutos) * 10) / 10,
	};
	const problemas = [
		typeof corpo.ficha !== "string" || !/^[0-9a-f]{64}$/.test(corpo.ficha),
		apelido.length === 0,
		!CLASSES.includes(corpo.classe),
		!RESULTADOS.includes(corpo.resultado),
		!(numeros.tentativas >= 1 && numeros.tentativas <= 999),
		!(numeros.mortes >= 0 && numeros.mortes <= 9999),
		!(numeros.minutos >= 0 && numeros.minutos <= 240),
		new TextEncoder().encode(dados).length > BYTES_DOS_EVENTOS,
	];
	if (problemas.some(Boolean)) {
		return { erro: "relatorio invalido" };
	}
	return { relatorio: { ficha: corpo.ficha, apelido, chave: chaveDoApelido(apelido), classe: corpo.classe, resultado: corpo.resultado, ...numeros, dados } };
}

function limparEvento(evento) {
	if (typeof evento !== "object" || evento === null || !TIPOS_DE_EVENTO.includes(evento.type)) {
		return null;
	}
	const limpo = { type: evento.type, t: numero(evento.t), attempt: numero(evento.attempt) };
	if (Number.isFinite(evento.groups_left)) {
		limpo.groups_left = numero(evento.groups_left);
	}
	if (Array.isArray(evento.position) && evento.position.length === 3 && evento.position.every(Number.isFinite)) {
		limpo.position = evento.position.map(numero);
	}
	if (typeof evento.buff === "string") {
		limpo.buff = evento.buff.slice(0, 40);
	}
	if (Array.isArray(evento.buffs)) {
		limpo.buffs = evento.buffs.filter((buff) => typeof buff === "string").slice(0, 10).map((buff) => buff.slice(0, 40));
	}
	return limpo;
}

function numero(valor) {
	const convertido = Math.round(Number(valor) * 10) / 10;
	return Number.isFinite(convertido) ? convertido : 0;
}
