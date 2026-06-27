import 'dart:typed_data';
import 'package:pdfx/pdfx.dart';

/// Serviço responsável por transformar um PDF (em bytes) em imagem(ns).
///
/// O modelo de visão da IA (Groq llama-4-scout) só entende imagens, não PDF.
/// Então, para a IA conseguir "ler" um documento PDF e compará-lo com o banco
/// de imagens, primeiro renderizamos a(s) página(s) do PDF como imagem PNG e
/// reutilizamos exatamente o mesmo fluxo já usado para imagens.
class PdfService {
  /// Renderiza a PRIMEIRA página de um PDF e devolve os bytes PNG da imagem.
  ///
  /// [pdfBytes]   → conteúdo bruto do PDF (Uint8List).
  /// [larguraMax] → maior dimensão desejada em pixels (a proporção é mantida).
  ///
  /// Retorna `null` se não for possível renderizar.
  static Future<Uint8List?> primeiraPaginaComoImagem(
    Uint8List pdfBytes, {
    double larguraMax = 1600,
  }) async {
    final paginas = await paginasComoImagens(
      pdfBytes,
      maxPaginas: 1,
      larguraMax: larguraMax,
    );
    return paginas.isNotEmpty ? paginas.first : null;
  }

  /// Renderiza até [maxPaginas] páginas do PDF e devolve a lista de imagens
  /// (PNG) correspondentes, na ordem das páginas.
  ///
  /// Usa PNG porque é o único formato suportado em todas as plataformas
  /// (inclusive Web) pelo pdfx.
  static Future<List<Uint8List>> paginasComoImagens(
    Uint8List pdfBytes, {
    int maxPaginas = 1,
    double larguraMax = 1600,
  }) async {
    final List<Uint8List> imagens = [];
    PdfDocument? documento;

    try {
      documento = await PdfDocument.openData(pdfBytes);

      final totalPaginas = documento.pagesCount;
      final qtd = totalPaginas < maxPaginas ? totalPaginas : maxPaginas;

      for (int n = 1; n <= qtd; n++) {
        final pagina = await documento.getPage(n);
        try {
          // Escala para que a maior dimensão fique ~larguraMax,
          // preservando a proporção original da página.
          final maiorLado =
              pagina.width > pagina.height ? pagina.width : pagina.height;
          final escala = maiorLado > 0 ? (larguraMax / maiorLado) : 1.0;

          final imagem = await pagina.render(
            width: pagina.width * escala,
            height: pagina.height * escala,
            format: PdfPageImageFormat.png,
          );

          if (imagem != null) {
            imagens.add(imagem.bytes);
          }
        } finally {
          await pagina.close();
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[PdfService] Erro ao renderizar PDF: $e');
    } finally {
      await documento?.close();
    }

    return imagens;
  }
}
