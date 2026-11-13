// Formato das mensagens binarias entre o jogo e a sala. Cada mensagem WebSocket junta varios pacotes
// do Godot (o jogo agrupa para gastar menos requisicoes). Cada pacote e um registro:
//   par (int32) | canal (uint8) | modo (uint8) | tamanho (uint32) | dados
// Do jogo para a sala, "par" e o destino: 0 = todos, N = so o N, -N = todos menos o N.
// Da sala para o jogo, "par" e quem mandou, carimbado pela sala.

export const CABECALHO = 10;
// o jogo junta algumas dezenas de pacotes por lote; milhares de registros vazios so servem para gastar CPU
export const MAX_REGISTROS = 512;

export function lerRegistros(buffer) {
	const dados = new Uint8Array(buffer);
	const visao = new DataView(dados.buffer, dados.byteOffset, dados.byteLength);
	const registros = [];
	let pos = 0;
	while (pos < dados.byteLength) {
		if (dados.byteLength - pos < CABECALHO || registros.length >= MAX_REGISTROS) {
			return null;
		}
		const par = visao.getInt32(pos, true);
		const canal = visao.getUint8(pos + 4);
		const modo = visao.getUint8(pos + 5);
		const tamanho = visao.getUint32(pos + 6, true);
		pos += CABECALHO;
		if (dados.byteLength - pos < tamanho) {
			return null;
		}
		registros.push({ par, canal, modo, dados: dados.subarray(pos, pos + tamanho) });
		pos += tamanho;
	}
	return registros;
}

export function escreverRegistros(registros) {
	const total = registros.reduce((soma, registro) => soma + CABECALHO + registro.dados.byteLength, 0);
	const saida = new Uint8Array(total);
	const visao = new DataView(saida.buffer);
	let pos = 0;
	for (const registro of registros) {
		visao.setInt32(pos, registro.par, true);
		visao.setUint8(pos + 4, registro.canal);
		visao.setUint8(pos + 5, registro.modo);
		visao.setUint32(pos + 6, registro.dados.byteLength, true);
		saida.set(registro.dados, pos + CABECALHO);
		pos += CABECALHO + registro.dados.byteLength;
	}
	return saida;
}

// quem recebe um pacote mandado por "remetente" com o destino "alvo", entre os pares da sala
export function destinatarios(alvo, remetente, pares) {
	if (alvo === 0) {
		return pares.filter((par) => par !== remetente);
	}
	if (alvo < 0) {
		return pares.filter((par) => par !== remetente && par !== -alvo);
	}
	return alvo !== remetente && pares.includes(alvo) ? [alvo] : [];
}

const ALFABETO = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const TAMANHO_CODIGO = 6;

// 31 simbolos sem os que se confundem (0/O, 1/I/L): 6 letras dao uns 30 bits
export function novoCodigo() {
	const sorteio = crypto.getRandomValues(new Uint8Array(TAMANHO_CODIGO));
	return Array.from(sorteio, (byte) => ALFABETO[byte % ALFABETO.length]).join("");
}

export function codigoValido(codigo) {
	return typeof codigo === "string" && codigo.length === TAMANHO_CODIGO && [...codigo].every((letra) => ALFABETO.includes(letra));
}

// o id 1 e sempre o host; clientes usam o id que propuseram, se for valido e estiver livre
export const ID_HOST = 1;
export const ID_MAXIMO = 2147483647;

export function idDeClienteValido(id, ocupados) {
	return Number.isInteger(id) && id > ID_HOST && id <= ID_MAXIMO && !ocupados.includes(id);
}
