import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:portix/core/ads/adblock_detector.dart';

/// Resolver fake: mapa host → veredito.
///   'nx'  → NXDOMAIN (bloqueio por DNS)
///   'bh'  → blackhole 0.0.0.0 (bloqueio por afogamento)
///   lista → endereços honestos
class _FakeResolver implements HostResolver {
  _FakeResolver(this.table);

  final Map<String, Object?> table;

  @override
  Future<List<String>> resolve(String host) async {
    final Object? value = table[host];
    if (value == 'nx') {
      throw const SocketException('NXDOMAIN');
    }
    if (value == 'bh') {
      return <String>['0.0.0.0'];
    }
    if (value is List<String>) {
      return value;
    }
    throw StateError('host $host não mapeado no fake');
  }
}

const List<String> _adHosts = <String>[
  'ads.unityads.unity3d.com',
  'auction.unityads.unity3d.com',
  'config.unityads.unity3d.com',
];

AdblockDetector _detector(Map<String, Object?> table) =>
    AdblockDetector(resolver: _FakeResolver(table));

void main() {
  test(
    'rede sã + todos os hosts de anúncio com NXDOMAIN → bloqueado',
    () async {
      final Map<String, Object?> table = <String, Object?>{
        'www.google.com': <String>['142.250.79.4'],
        for (final String host in _adHosts) host: 'nx',
      };
      expect(await _detector(table).detect(), AdblockVerdict.blocked);
    },
  );

  test('bloqueio por blackhole (0.0.0.0) também é detectado', () async {
    final Map<String, Object?> table = <String, Object?>{
      'www.google.com': <String>['142.250.79.4'],
      for (final String host in _adHosts) host: 'bh',
    };
    expect(await _detector(table).detect(), AdblockVerdict.blocked);
  });

  test('hosts de anúncio resolvendo normal → sem bloqueio', () async {
    final Map<String, Object?> table = <String, Object?>{
      'www.google.com': <String>['142.250.79.4'],
      for (final String host in _adHosts) host: <String>['104.18.30.1'],
    };
    expect(await _detector(table).detect(), AdblockVerdict.allowed);
  });

  test(
    'anti falso positivo: controle falhou (sem rede) → offline, nunca bloqueio',
    () async {
      final Map<String, Object?> table = <String, Object?>{
        for (final String host in _adHosts) host: 'nx',
      };
      expect(await _detector(table).detect(), AdblockVerdict.offline);
    },
  );

  test(
    'anti falso positivo: UM host de anúncio resolvendo já absolve o usuário',
    () async {
      final Map<String, Object?> table = <String, Object?>{
        'www.google.com': <String>['142.250.79.4'],
        'ads.unityads.unity3d.com': <String>['104.18.30.1'],
        'auction.unityads.unity3d.com': 'nx',
        'config.unityads.unity3d.com': 'bh',
      };
      expect(await _detector(table).detect(), AdblockVerdict.allowed);
    },
  );

  test('endereços de loopback contam como bloqueio (127.x, ::1, ::)', () async {
    final Map<String, Object?> table = <String, Object?>{
      'www.google.com': <String>['142.250.79.4'],
      'ads.unityads.unity3d.com': <String>['127.0.0.1'],
      'auction.unityads.unity3d.com': <String>['::1'],
      'config.unityads.unity3d.com': <String>['::'],
    };
    expect(await _detector(table).detect(), AdblockVerdict.blocked);
  });
}
