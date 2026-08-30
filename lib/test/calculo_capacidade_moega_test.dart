// Testes unitários da fórmula "Capacidade de Moega".
//
// Rodar com:  flutter test test/calculo_capacidade_moega_test.dart
//
// Regra testada:
//   ((A − 0,6) × (B − 0,6) × (C + D)) × M ÷ K
//   com M ∈ {480, 620} e K ∈ {40, 60}

import 'package:flutter_test/flutter_test.dart';
import 'package:aividade_pi_marcelo/utils/calculo_capacidade_moega.dart';

void main() {
  group('calcularCapacidadeMoega — casos válidos', () {
    test('Caso 1: valores inteiros simples (M=480, K=40)', () {
      // A'=1,4  B'=2,4  →  1,4×2,4=3,36
      // R1 = 3,36×1 = 3,36 ; R2 = 3,36×1 = 3,36 ; Soma = 6,72
      // 6,72 × 480 = 3225,6 ; ÷ 40 = 80,64
      final r = calcularCapacidadeMoega(
          a: 2, b: 3, c: 1, d: 1, multiplicador: 480, divisor: 40);
      expect(r.aCorrigido, closeTo(1.4, 1e-9));
      expect(r.bCorrigido, closeTo(2.4, 1e-9));
      expect(r.resultado1, closeTo(3.36, 1e-9));
      expect(r.resultado2, closeTo(3.36, 1e-9));
      expect(r.somaTotal, closeTo(6.72, 1e-9));
      expect(r.valorMultiplicado, closeTo(3225.6, 1e-9));
      expect(r.resultadoFinal, closeTo(80.64, 1e-9));
    });

    test('Caso 2: valores decimais (M=620, K=60)', () {
      // A'=2,9  B'=2,2  →  6,38 ; C+D = 2,1 → Soma = 13,398
      // 13,398 × 620 = 8306,76 ; ÷ 60 = 138,446
      final r = calcularCapacidadeMoega(
          a: 3.5, b: 2.8, c: 1.2, d: 0.9, multiplicador: 620, divisor: 60);
      expect(r.somaTotal, closeTo(13.398, 1e-9));
      expect(r.resultadoFinal, closeTo(138.446, 1e-3));
    });

    test(
        'Caso 3: propriedade — R1 + R2 equivale à forma fatorada '
        "A'×B'×(C+D)", () {
      const a = 4.7, b = 1.9, c = 2.35, d = 0.75;
      final r = calcularCapacidadeMoega(
          a: a, b: b, c: c, d: d, multiplicador: 480, divisor: 60);
      final fatorado = (a - 0.6) * (b - 0.6) * (c + d);
      expect(r.somaTotal, closeTo(fatorado, 1e-9));
    });

    test('Caso 4: extremo inferior — C = 0 e D = 0 resultam em 0', () {
      final r = calcularCapacidadeMoega(
          a: 5, b: 5, c: 0, d: 0, multiplicador: 480, divisor: 40);
      expect(r.resultadoFinal, 0);
    });

    test('Caso 5: extremo superior — valores grandes não estouram double', () {
      final r = calcularCapacidadeMoega(
          a: 1000, b: 1000, c: 500, d: 500, multiplicador: 620, divisor: 40);
      expect(r.resultadoFinal.isFinite, isTrue);
      // (999,4 × 999,4 × 1000) × 620 ÷ 40 = 999,4² × 15500
      expect(r.resultadoFinal, closeTo(999.4 * 999.4 * 1000 * 620 / 40, 1));
    });
  });

  group('calcularCapacidadeMoega — validações e bordas inválidas', () {
    test('A = 0,6 (correção viraria zero) lança ArgumentError', () {
      expect(
        () => calcularCapacidadeMoega(
            a: 0.6, b: 3, c: 1, d: 1, multiplicador: 480, divisor: 40),
        throwsArgumentError,
      );
    });

    test('B < 0,6 (correção viraria negativa) lança ArgumentError', () {
      expect(
        () => calcularCapacidadeMoega(
            a: 3, b: 0.5, c: 1, d: 1, multiplicador: 480, divisor: 40),
        throwsArgumentError,
      );
    });

    test('C negativo lança ArgumentError', () {
      expect(
        () => calcularCapacidadeMoega(
            a: 3, b: 3, c: -1, d: 1, multiplicador: 480, divisor: 40),
        throwsArgumentError,
      );
    });

    test('Multiplicador fora de {480, 620} lança ArgumentError', () {
      expect(
        () => calcularCapacidadeMoega(
            a: 3, b: 3, c: 1, d: 1, multiplicador: 500, divisor: 40),
        throwsArgumentError,
      );
    });

    test(
        'Divisor 0 ou fora de {40, 60} lança ArgumentError '
        '(nunca há divisão por zero)', () {
      expect(
        () => calcularCapacidadeMoega(
            a: 3, b: 3, c: 1, d: 1, multiplicador: 480, divisor: 0),
        throwsArgumentError,
      );
      expect(
        () => calcularCapacidadeMoega(
            a: 3, b: 3, c: 1, d: 1, multiplicador: 480, divisor: 50),
        throwsArgumentError,
      );
    });
  });
}
