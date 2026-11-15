/// Configuração central da monetização (Unity Ads).
///
/// Tudo que o time ajusta no dashboard da Unity (Game ID, placements,
/// frequência) tem espelho aqui com nome explícito — nenhum número mágico
/// espalhado pelo app.
class AdsConfig {
  const AdsConfig._();

  /// Unity Ads Game ID (Android) do projeto — Unity Dashboard → Monetization.
  /// O app não tem build iOS hoje; quando existir, acrescente o ID iOS aqui.
  static const String androidGameId = '6225452';

  /// Placements padrão que a Unity cria para novos projetos (podem ser
  /// renomeados no dashboard — mantenha em sincronia com este arquivo).
  static const String interstitialPlacement = 'Interstitial_Android';
  static const String rewardedPlacement = 'Rewarded_Android';

  /// Interstitial aparece na CONCLUSÃO de um download (momento de valor, o
  /// usuário acabou de receber o que veio buscar), nunca nas primeiras
  /// sessões e respeitando o cooldown mínimo entre exibições.
  static const int skipFirstSessions = 1;
  static const Duration interstitialCooldown = Duration(minutes: 3);

  /// Detecção de bloqueador: hosts de infra da Unity Ads + um host de
  /// controle (rede sã). Bloqueio só é acusado quando o CONTROLE resolve e
  /// TODOS os hosts de anúncio falham/retornam lixo — isso evita punir
  /// usuário com DNS instável ou rede ruim (falso positivo).
  static const List<String> adHosts = <String>[
    'ads.unityads.unity3d.com',
    'auction.unityads.unity3d.com',
    'config.unityads.unity3d.com',
  ];
  static const String controlHost = 'www.google.com';
  static const Duration lookupTimeout = Duration(seconds: 3);
}
