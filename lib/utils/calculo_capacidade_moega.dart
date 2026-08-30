/// Cálculo de capacidade de moega com desconto de borda.
///
/// Regra de negócio (notação algébrica):
///
///   A' = A − 0,6
///   B' = B − 0,6
///   R1 = A' × B' × C
///   R2 = A' × B' × D
///   S  = R1 + R2                (equivalente a A' × B' × (C + D))
///   V  = S × M                  (M ∈ {480, 620})
///   Resultado = V ÷ K           (K ∈ {40, 60})
///
/// Mantido como função pura (sem Flutter, sem estado) para permitir
/// teste unitário direto em `test/calculo_capacidade_moega_test.dart`
/// e reuso futuro fora da HomePage.
library;

/// Desconto fixo aplicado às medidas A e B.
const double kDescontoBorda = 0.6;

/// Multiplicadores permitidos pela regra de negócio.
const List<double> kMultiplicadoresValidos = [480, 620];

/// Divisores permitidos pela regra de negócio.
const List<double> kDivisoresValidos = [40, 60];

/// Resultado detalhado do cálculo, com os valores intermediários
/// (útil para montar a "memória de cálculo" exibida no chat).
class ResultadoCapacidadeMoega {
  final double aCorrigido;
  final double bCorrigido;
  final double resultado1;
  final double resultado2;
  final double somaTotal;
  final double valorMultiplicado;
  final double resultadoFinal;

  const ResultadoCapacidadeMoega({
    required this.aCorrigido,
    required this.bCorrigido,
    required this.resultado1,
    required this.resultado2,
    required this.somaTotal,
    required this.valorMultiplicado,
    required this.resultadoFinal,
  });
}

/// Executa o cálculo completo, validando as entradas.
///
/// Lança [ArgumentError] quando:
/// * `a` ou `b` ≤ 0,6 — a correção (valor − 0,6) resultaria em zero ou
///   negativo, o que não tem sentido físico para uma medida;
/// * `c` ou `d` < 0 — medidas não podem ser negativas;
/// * `multiplicador` não é 480 nem 620;
/// * `divisor` não é 40 nem 60 (isso também elimina, por construção,
///   qualquer possibilidade de divisão por zero).
ResultadoCapacidadeMoega calcularCapacidadeMoega({
  required double a,
  required double b,
  required double c,
  required double d,
  required double multiplicador,
  required double divisor,
}) {
  // ── Validações de borda ────────────────────────────────────────────
  if (a.isNaN || b.isNaN || c.isNaN || d.isNaN) {
    throw ArgumentError('As medidas não podem ser NaN.');
  }
  if (a <= kDescontoBorda) {
    throw ArgumentError.value(
      a,
      'a',
      'A precisa ser maior que $kDescontoBorda — a correção '
          '(A − $kDescontoBorda) resultaria em valor zero ou negativo.',
    );
  }
  if (b <= kDescontoBorda) {
    throw ArgumentError.value(
      b,
      'b',
      'B precisa ser maior que $kDescontoBorda — a correção '
          '(B − $kDescontoBorda) resultaria em valor zero ou negativo.',
    );
  }
  if (c < 0) {
    throw ArgumentError.value(c, 'c', 'C não pode ser negativo.');
  }
  if (d < 0) {
    throw ArgumentError.value(d, 'd', 'D não pode ser negativo.');
  }
  if (!kMultiplicadoresValidos.contains(multiplicador)) {
    throw ArgumentError.value(
      multiplicador,
      'multiplicador',
      'Valor inválido — os multiplicadores aceitos são '
          '${kMultiplicadoresValidos.join(" ou ")}.',
    );
  }
  // Validação defensiva de divisão por zero: por construção o divisor
  // só pode ser 40 ou 60, mas o guard explícito protege chamadas futuras
  // caso a lista de divisores válidos seja alterada.
  if (divisor == 0) {
    throw ArgumentError.value(divisor, 'divisor', 'Divisor não pode ser 0.');
  }
  if (!kDivisoresValidos.contains(divisor)) {
    throw ArgumentError.value(
      divisor,
      'divisor',
      'Valor inválido — os divisores aceitos são '
          '${kDivisoresValidos.join(" ou ")}.',
    );
  }

  // ── Passo 1: correção inicial (subtrair 0,6 dos DOIS primeiros) ───
  final aCorrigido = a - kDescontoBorda;
  final bCorrigido = b - kDescontoBorda;

  // ── Passo 2: cálculo das partes ────────────────────────────────────
  final resultado1 = aCorrigido * bCorrigido * c;
  final resultado2 = aCorrigido * bCorrigido * d;

  // ── Passo 3: soma dos resultados ───────────────────────────────────
  final somaTotal = resultado1 + resultado2;

  // ── Passo 4: multiplicação (480 ou 620) ────────────────────────────
  final valorMultiplicado = somaTotal * multiplicador;

  // ── Passo 5: divisão (40 ou 60) ────────────────────────────────────
  final resultadoFinal = valorMultiplicado / divisor;

  return ResultadoCapacidadeMoega(
    aCorrigido: aCorrigido,
    bCorrigido: bCorrigido,
    resultado1: resultado1,
    resultado2: resultado2,
    somaTotal: somaTotal,
    valorMultiplicado: valorMultiplicado,
    resultadoFinal: resultadoFinal,
  );
}

/// Formata um double sem casas decimais desnecessárias
/// (480.0 → "480"; 3.36 → "3.36"). Usado nas mensagens do chat.
String formatarNumero(double n) =>
    n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
