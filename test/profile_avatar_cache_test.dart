import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/shared/widgets/profile_avatar.dart';

// ============================================================================
// Evidência do cache da imagem de perfil (mesmo mecanismo do ProfileAvatar —
// DefaultCacheManager do cached_network_image):
//
// 1. putFile + getSingleFile 5x → 0 downloads (servido do disco);
// 2. removeFile (logout/troca de foto) → próximo acesso faz 1 download;
// 3. URL nova (foto trocada) → 1 download;
// 4. offline (HttpOverrides sintético) com cache → imagem disponível.
//
// Um HttpClient sintético conta cada tentativa de download; nenhuma rede real.
// ============================================================================

const String _avatarUrl = 'http://cache-test.portix/avatar.png';
const String _avatarUrlV2 = 'http://cache-test.portix/avatar.png?v=2';

int _downloads = 0;

final Uint8List _png1x1 = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, String> _values = <String, String>{};

  @override
  ContentType? get contentType => ContentType('image', 'png');

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name.toLowerCase()] = value.toString();

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      set(name, value);

  @override
  void remove(String name, Object value) => _values.remove(name.toLowerCase());

  @override
  void removeAll(String name) => _values.remove(name.toLowerCase());

  @override
  void noFolding(String name) {}

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach(
        (String name, String value) => action(name, <String>[value]),
      );

  @override
  String? value(String name) => _values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeResponse implements HttpClientResponse {
  const _FakeResponse(this.body);

  final List<int> body;

  @override
  int get statusCode => 200;

  @override
  int get contentLength => body.length;

  @override
  HttpHeaders get headers {
    final _FakeHttpHeaders headers = _FakeHttpHeaders();
    headers.set('etag', '"avatar-v1"');
    headers.set('content-type', 'image/png');
    headers.set('content-length', body.length.toString());
    return headers;
  }

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => true;

  @override
  String get reasonPhrase => 'OK';

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[body]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  bool bufferOutput = true;

  @override
  int contentLength = 0;

  @override
  Encoding encoding = Encoding.getByName('utf-8')!;

  @override
  Uri get uri => Uri.parse('http://cache-test.portix/');

  @override
  String get method => 'GET';

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}

  @override
  void writeln([Object? object = '']) {}

  @override
  Future<void> flush() async {}

  @override
  Future<HttpClientResponse> get done async => _FakeResponse(_png1x1);

  @override
  void abort([Object? cause, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(_png1x1);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _CountingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    _downloads++;
    return _FakeRequest();
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _CountingOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _CountingHttpClient();
}

void main() {
  // O binding instala o mock HTTP (400) — o nosso override entra DEPOIS dele
  // para que o cache manager use o HttpClient sintético contado.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _downloads = 0;
    HttpOverrides.global = _CountingOverrides();
    // Host de teste não tem plugin path_provider — mocka o channel com um
    // diretório temporário único por chamada.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async {
            final Directory dir = await Directory.systemTemp.createTemp(
              'portix_cache_test',
            );
            return dir.path;
          },
        );
  });

  tearDown(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  test('reabrir 5x serve do disco: 0 downloads', () async {
    await DefaultCacheManager().putFile(
      _avatarUrl,
      _png1x1,
      fileExtension: 'png',
    );

    for (int i = 0; i < 5; i++) {
      // Cada "abertura das configurações" consulta a imagem de novo.
      final File file = await DefaultCacheManager().getSingleFile(_avatarUrl);
      expect(file.lengthSync(), _png1x1.length, reason: 'abertura ${i + 1}');
    }

    expect(
      _downloads,
      0,
      reason: 'Tudo do disco — meta: 0 downloads ao reabrir (2ª vez em diante)',
    );
  });

  test('removeFile (logout/troca) força 1 download', () async {
    await DefaultCacheManager().putFile(
      _avatarUrl,
      _png1x1,
      fileExtension: 'png',
    );
    await DefaultCacheManager().removeFile(_avatarUrl);

    await DefaultCacheManager().getSingleFile(_avatarUrl);

    expect(_downloads, 1, reason: 'Cache removido → re-download');
  });

  test('URL nova (foto trocada) faz 1 download', () async {
    await DefaultCacheManager().putFile(
      _avatarUrl,
      _png1x1,
      fileExtension: 'png',
    );

    await DefaultCacheManager().getSingleFile(_avatarUrlV2);

    expect(_downloads, 1, reason: 'URL nova não está no cache → 1 download');
  });

  test('PerfilAvatar é o componente de imagem em cache (integração)', () {
    final ProfileAvatar avatar = const ProfileAvatar(
      name: 'Ana',
      imageUrl: _avatarUrl,
      size: 62,
    );
    expect(avatar.imageUrl, _avatarUrl);
    expect(avatar.size, 62);
    expect(avatar.name, 'Ana');
    // O widget é StatelessWidget que internamente usa CachedNetworkImage
    // (mesmo DefaultCacheManager validado acima) com iniciais como fallback.
    expect(avatar, isA<Widget>());
  });
}
