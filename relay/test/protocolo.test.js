import { test } from "node:test";
import assert from "node:assert/strict";
import { codigoValido, destinatarios, escreverRegistros, idDeClienteValido, lerRegistros, MAX_REGISTROS, novoCodigo } from "../src/protocolo.js";

test("registros voltam iguais depois de escritos e lidos", () => {
	const enviados = [
		{ par: 0, canal: 0, modo: 2, dados: new Uint8Array([1, 2, 3]) },
		{ par: -7, canal: 3, modo: 0, dados: new Uint8Array([]) },
		{ par: 12345, canal: 1, modo: 1, dados: new Uint8Array(500).fill(9) },
	];

	const lidos = lerRegistros(escreverRegistros(enviados));

	assert.equal(lidos.length, 3);
	assert.deepEqual(lidos.map((registro) => [registro.par, registro.canal, registro.modo, [...registro.dados]]), enviados.map((registro) => [registro.par, registro.canal, registro.modo, [...registro.dados]]));
});

test("mensagem cortada no meio e recusada", () => {
	const inteira = escreverRegistros([{ par: 1, canal: 0, modo: 0, dados: new Uint8Array(20) }]);

	assert.equal(lerRegistros(inteira.subarray(0, 15)), null);
	assert.equal(lerRegistros(inteira.subarray(0, 4)), null);
});

test("tamanho declarado maior que a mensagem e recusado", () => {
	const mentira = escreverRegistros([{ par: 1, canal: 0, modo: 0, dados: new Uint8Array(4) }]);
	new DataView(mentira.buffer).setUint32(6, 99999, true);

	assert.equal(lerRegistros(mentira), null);
});

test("mensagem com registros demais e recusada", () => {
	const vazios = Array.from({ length: MAX_REGISTROS + 1 }, () => ({ par: 0, canal: 0, modo: 0, dados: new Uint8Array() }));

	assert.equal(lerRegistros(escreverRegistros(vazios)), null);
	assert.equal(lerRegistros(escreverRegistros(vazios.slice(1))).length, MAX_REGISTROS);
});

test("destino 0 vai para todos menos quem mandou", () => {
	assert.deepEqual(destinatarios(0, 5, [1, 5, 9]), [1, 9]);
});

test("destino negativo exclui quem mandou e o par indicado", () => {
	assert.deepEqual(destinatarios(-9, 5, [1, 5, 9, 12]), [1, 12]);
});

test("destino direto so vale para par que esta na sala", () => {
	assert.deepEqual(destinatarios(9, 5, [1, 5, 9]), [9]);
	assert.deepEqual(destinatarios(42, 5, [1, 5, 9]), []);
	assert.deepEqual(destinatarios(5, 5, [1, 5, 9]), []);
});

test("codigo sorteado tem 6 letras do alfabeto sem ambiguas", () => {
	for (let i = 0; i < 200; i++) {
		const codigo = novoCodigo();
		assert.ok(codigoValido(codigo), codigo);
		assert.ok(!/[01OIL]/.test(codigo), codigo);
	}
});

test("codigo com letra ambigua, minuscula ou tamanho errado e invalido", () => {
	assert.equal(codigoValido("ABC0EF"), false);
	assert.equal(codigoValido("abcdef"), false);
	assert.equal(codigoValido("ABCDE"), false);
	assert.equal(codigoValido(undefined), false);
});

test("cliente nao pode usar o id do host, um id ocupado ou fora do intervalo", () => {
	assert.equal(idDeClienteValido(1, []), false);
	assert.equal(idDeClienteValido(77, [1, 77]), false);
	assert.equal(idDeClienteValido(2 ** 31, []), false);
	assert.equal(idDeClienteValido(3.5, []), false);
	assert.equal(idDeClienteValido(77, [1]), true);
});
