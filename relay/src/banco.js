// acesso ao D1 (migrations/): consumo das partidas, fichas, telemetria e placar. Todo SQL do relay fica aqui

const DIA_MS = 24 * 60 * 60 * 1000;
const APAGAR_POR_VEZ = 200;
const MAX_LOTES_DE_APAGAR = 40;
const FICHAS_POR_PARTIDA = 8;
// partida que nunca fechou (a sala caiu sem passar pelo encerramento) entra no orcamento por esta estimativa
const PARTIDA_ORFA_APOS_MS = 3 * 60 * 60 * 1000;
export const REQUISICOES_PARTIDA_ORFA = 4000;

export function diaUtc(momento) {
	return new Date(momento).toISOString().slice(0, 10);
}

export async function abrirPartida(db, id, agora) {
	await db.prepare("INSERT INTO partidas (id, dia, inicio) VALUES (?, ?, ?)").bind(id, diaUtc(agora), agora).run();
}

// reserva que perdeu a corrida pela ultima vaga: a partida nunca existiu
export async function descartarPartida(db, id) {
	if (id) {
		await db.prepare("DELETE FROM partidas WHERE id = ? AND fim IS NULL").bind(id).run();
	}
}

// gravado a cada entrada: o placar so aceita relatorio de partida que teve grupo de verdade
export async function contarJogadores(db, id, jogadores) {
	await db.prepare("UPDATE partidas SET jogadores = MAX(jogadores, ?) WHERE id = ?").bind(Math.min(jogadores, 4), id).run();
}

// so a primeira chamada vale: uma segunda nao sobrescreve o consumo
export async function fecharPartida(db, id, { fim, minutos, jogadores, mensagens, bytes, requisicoes }) {
	const resultado = await db
		.prepare("UPDATE partidas SET fim = ?, minutos = ?, jogadores = MAX(jogadores, ?), mensagens = ?, bytes = ?, requisicoes = ? WHERE id = ? AND fim IS NULL")
		.bind(fim, minutos, Math.min(jogadores, 4), mensagens, bytes, requisicoes, id)
		.run();
	return resultado.meta.changes === 1;
}

export async function usoDoDia(db, dia) {
	const linha = await db
		.prepare("SELECT COALESCE(SUM(requisicoes), 0) AS requisicoes, COUNT(*) AS partidas, SUM(fim IS NOT NULL) AS encerradas FROM partidas WHERE dia = ?")
		.bind(dia)
		.first();
	return { dia, requisicoes: linha.requisicoes, partidas: linha.partidas, encerradas: linha.encerradas ?? 0 };
}

// a ficha vai para o jogador; o banco guarda so o hash. Reconectar sem parar nao gera fichas sem fim
export async function criarFicha(db, partidaId, agora) {
	const ficha = `${crypto.randomUUID()}${crypto.randomUUID()}`.replaceAll("-", "");
	const resultado = await db
		.prepare("INSERT INTO fichas (hash, partida_id, criada) SELECT ?1, ?2, ?3 WHERE (SELECT COUNT(*) FROM fichas WHERE partida_id = ?2) < ?4")
		.bind(await hash(ficha), partidaId, agora, FICHAS_POR_PARTIDA)
		.run();
	return resultado.meta.changes === 1 ? ficha : "";
}

// a ficha precisa estar livre, ser de uma partida com 2 ou mais jogadores e os minutos informados nao podem
// passar da duracao real da partida (sem isso, alguem sozinho postaria vitorias para o placar)
const FICHA_VALE = `FROM fichas f JOIN partidas p ON p.id = f.partida_id
	WHERE f.hash = ?1 AND f.usada IS NULL AND f.criada > ?2 AND p.jogadores >= 2 AND ?3 <= (?4 - p.inicio) / 60000.0 + 1`;

// grava o relatorio, soma no placar e queima a ficha numa transacao so: duas chamadas com a mesma
// ficha nunca gravam duas vezes, e ficha recusada nao mexe no placar
export async function registrarTelemetria(db, relatorio, agora) {
	const condicao = [await hash(relatorio.ficha), agora - DIA_MS, relatorio.minutos, agora];
	const vitoria = relatorio.resultado === "victory" ? 1 : 0;
	const [insercao] = await db.batch([
		db
			.prepare(
				`INSERT INTO telemetria (partida_id, apelido, apelido_chave, classe, resultado, tentativas, mortes, minutos, dados, criada)
				SELECT f.partida_id, ?5, ?6, ?7, ?8, ?9, ?10, ?3, ?11, ?4 ${FICHA_VALE}`,
			)
			.bind(...condicao, relatorio.apelido, relatorio.chave, relatorio.classe, relatorio.resultado, relatorio.tentativas, relatorio.mortes, relatorio.dados),
		db
			.prepare(
				`INSERT INTO placar (apelido_chave, apelido, partidas, vitorias, melhor_tentativa)
				SELECT ?5, ?6, 1, ?7, CASE WHEN ?7 = 1 THEN ?8 END ${FICHA_VALE}
				ON CONFLICT (apelido_chave) DO UPDATE SET
					apelido = excluded.apelido,
					partidas = partidas + 1,
					vitorias = vitorias + excluded.vitorias,
					melhor_tentativa = CASE
						WHEN excluded.melhor_tentativa IS NULL THEN melhor_tentativa
						WHEN melhor_tentativa IS NULL THEN excluded.melhor_tentativa
						ELSE MIN(melhor_tentativa, excluded.melhor_tentativa) END`,
			)
			.bind(...condicao, relatorio.chave, relatorio.apelido, vitoria, relatorio.tentativas),
		db.prepare(`UPDATE fichas SET usada = ?4 WHERE hash IN (SELECT f.hash ${FICHA_VALE})`).bind(...condicao),
	]);
	return insercao.meta.changes === 1;
}

export async function placar(db, limite = 20) {
	const { results } = await db
		.prepare("SELECT apelido, partidas, vitorias, melhor_tentativa FROM placar ORDER BY vitorias DESC, melhor_tentativa, partidas DESC LIMIT ?")
		.bind(limite)
		.all();
	return results;
}

// pedido do titular (LGPD): some tudo que o apelido gerou, no placar e na telemetria
export async function apagarApelido(db, chave) {
	const [telemetria] = await db.batch([
		db.prepare("DELETE FROM telemetria WHERE apelido_chave = ?").bind(chave),
		db.prepare("DELETE FROM placar WHERE apelido_chave = ?").bind(chave),
	]);
	return telemetria.meta.changes;
}

// limpeza diaria: partida antiga leva fichas e telemetria (cascade), ficha velha sai, partida orfa fecha
// com a estimativa e o placar e recontado a partir do que sobrou
export async function limpezaDiaria(db, agora, retencaoDias) {
	const limiteDia = diaUtc(agora - retencaoDias * DIA_MS);
	let apagadas = 0;
	for (let lote = 0; lote < MAX_LOTES_DE_APAGAR; lote++) {
		const resultado = await db
			.prepare("DELETE FROM partidas WHERE id IN (SELECT id FROM partidas WHERE dia < ? LIMIT ?)")
			.bind(limiteDia, APAGAR_POR_VEZ)
			.run();
		apagadas += resultado.meta.changes;
		if (resultado.meta.changes === 0) {
			break;
		}
	}
	await db.batch([
		db.prepare("DELETE FROM fichas WHERE criada < ?").bind(agora - DIA_MS),
		db.prepare("UPDATE partidas SET fim = inicio, minutos = 0, requisicoes = ? WHERE fim IS NULL AND inicio < ?").bind(REQUISICOES_PARTIDA_ORFA, agora - PARTIDA_ORFA_APOS_MS),
		db.prepare("DELETE FROM placar"),
		db.prepare(
			`INSERT INTO placar (apelido_chave, apelido, partidas, vitorias, melhor_tentativa)
			SELECT apelido_chave, MAX(apelido), COUNT(*), SUM(resultado = 'victory'), MIN(CASE WHEN resultado = 'victory' THEN tentativas END)
			FROM telemetria GROUP BY apelido_chave`,
		),
	]);
	return apagadas;
}

export async function hash(texto) {
	const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto));
	return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
