import 'parsing.dart';

/// Relato público de como um jogo roda num aparelho (sem expor o user_id).
class CompatReport {
  const CompatReport({
    required this.author,
    required this.status,
    this.authorCover,
    this.brand,
    this.model,
    this.soc,
    this.gpu,
    this.ramGb,
    this.createdAt,
  });

  final String author;
  final String? authorCover;
  final String status;
  final String? brand;
  final String? model;
  final String? soc;
  final String? gpu;
  final int? ramGb;
  final DateTime? createdAt;

  /// "Marca Modelo" (ou o que existir).
  String get deviceLabel {
    final List<String> parts = <String>[
      if (brand != null) brand!,
      if (model != null) model!,
    ];
    return parts.isEmpty ? 'Aparelho' : parts.join(' ');
  }

  factory CompatReport.fromMap(Map<String, dynamic> map) => CompatReport(
        author: asTextOr(map['author'], 'Jogador'),
        status: asTextOr(map['status'], 'good'),
        authorCover: asText(map['author_cover']),
        brand: asText(map['brand']),
        model: asText(map['model']),
        soc: asText(map['soc']),
        gpu: asText(map['gpu']),
        ramGb: map['ram_gb'] == null ? null : asInt(map['ram_gb']),
        createdAt: asDate(map['created_at']),
      );
}
