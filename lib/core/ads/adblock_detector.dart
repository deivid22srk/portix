import 'dart:async';
import 'dart:io';

import 'ads_config.dart';

/// Veredito da detecção de bloqueador de anúncios.
enum AdblockVerdict {
  /// Sem bloqueio (ou bloqueio parcial — não punimos o usuário).
  allowed,

  /// Rede sã + todos os hosts de anúncio inalcançáveis/afogados.
  blocked,

  /// Host de CONTROLE também falhou: sem rede (ou rede muito restrita).
  /// Nunca acusar bloqueador aqui — o usuário offline não é culpado.
  offline,
}

/// Ponto de resolução DNS (injetável para testes).
abstract interface class HostResolver {
  /// Devolve os endereços do host; lança em NXDOMAIN/timeout.
  Future<List<String>> resolve(String host);
}

/// Resolver real via DNS do sistema. Bloqueadores (DNS privado, app de VPN,
/// /etc/hosts) respondem NXDOMAIN — vira exceção aqui — ou afogam o domínio
/// em `0.0.0.0`/`127.0.0.1`, ambos reconhecidos abaixo.
class SystemHostResolver implements HostResolver {
  const SystemHostResolver();

  @override
  Future<List<String>> resolve(String host) async {
    final List<InternetAddress> addresses = await InternetAddress.lookup(
      host,
    ).timeout(AdsConfig.lookupTimeout);
    return addresses.map((InternetAddress address) => address.address).toList();
  }
}

/// Detecta bloqueador de anúncios comparando a resolução dos hosts da Unity
/// Ads com um host de controle. Estratégia conservadora: só acusa quando
/// TODOS os hosts de anúncio falham — um único host resolvendo já é sinal de
/// que a rede do usuário está honesta.
class AdblockDetector {
  const AdblockDetector({HostResolver? resolver})
    : _resolver = resolver ?? const SystemHostResolver();

  final HostResolver _resolver;

  Future<AdblockVerdict> detect() async {
    // 1) Host de controle: sem rede sã não existe veredito de bloqueio.
    if (!await _resolves(_resolver, AdsConfig.controlHost)) {
      return AdblockVerdict.offline;
    }
    // 2) Todos os hosts de anúncio precisam estar afogados para acusar.
    for (final String host in AdsConfig.adHosts) {
      if (await _resolves(_resolver, host)) {
        return AdblockVerdict.allowed;
      }
    }
    return AdblockVerdict.blocked;
  }
}

/// Endereço que um bloqueador devolve para "afogar" o domínio.
bool _isBlackhole(String address) =>
    address == '0.0.0.0' ||
    address.startsWith('127.') ||
    address == '::' ||
    address == '::1';

Future<bool> _resolves(HostResolver resolver, String host) async {
  try {
    final List<String> addresses = await resolver.resolve(host);
    return addresses.isNotEmpty &&
        addresses.any((String address) => !_isBlackhole(address));
  } on Object {
    // NXDOMAIN, timeout ou rede ausente: o host está inalcançável.
    return false;
  }
}
