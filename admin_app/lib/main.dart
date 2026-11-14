import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// PORTIX ADM — app separado de administração.
// Fala com o mesmo Supabase do PORTIX (RPCs admin_* protegidos por papel).
// ============================================================================

const String kEnvUrl = String.fromEnvironment('SUPABASE_URL');
const String kEnvKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const String kCfgUrl = 'cfg.url';
const String kCfgKey = 'cfg.key';

bool _supabaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  runApp(PortixAdminApp(prefs: prefs));
}

class PortixAdminApp extends StatelessWidget {
  const PortixAdminApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PORTIX ADM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _C.accent,
          brightness: Brightness.dark,
        ).copyWith(primary: _C.accent, secondary: _C.accentAlt, surface: _C.bg, error: _C.danger),
        scaffoldBackgroundColor: _C.bg,
        useMaterial3: true,
      ),
      home: _AdminHome(prefs: prefs),
    );
  }
}

class _AdminHome extends StatefulWidget {
  const _AdminHome({required this.prefs});

  final SharedPreferences prefs;

  @override
  State<_AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<_AdminHome> {
  bool _ready = false;
  bool _configured = false;
  bool _session = false;
  bool _busy = false;
  int _tab = 0;
  String? _error;
  String? _adminsError;
  String? _updatesError;
  String? _gamesError;
  Map<String, dynamic>? _role;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _admins = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _updates = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _games = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _platforms = <Map<String, dynamic>>[];
  int _gamesTotal = 0;
  String _gamesQuery = '';

  String get _email => Supabase.instance.client.auth.currentUser?.email ?? '';

  bool get _isRoot => _role?['level'] == 'root';

  bool get _canManageGames {
    if (_role == null) {
      return false;
    }
    if (_isRoot) {
      return true;
    }
    final Object? permissions = _role!['permissions'];
    if (permissions is Map) {
      return permissions['manage_games'] == true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final String url = kEnvUrl.isNotEmpty ? kEnvUrl : (widget.prefs.getString(kCfgUrl) ?? '');
    final String key = kEnvKey.isNotEmpty ? kEnvKey : (widget.prefs.getString(kCfgKey) ?? '');
    if (url.isNotEmpty && key.isNotEmpty) {
      try {
        await _initSupabase(url, key);
        _configured = true;
      } on Object catch (error) {
        _error = 'Falha ao conectar: $error';
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _ready = true);
    if (_configured) {
      await _afterAuth();
    }
  }

  Future<void> _initSupabase(String url, String key) async {
    if (_supabaseReady) {
      return;
    }
    await Supabase.initialize(url: url, publishableKey: key);
    _supabaseReady = true;
  }

  Future<void> _saveConfig(String url, String key) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.prefs.setString(kCfgUrl, url);
      await widget.prefs.setString(kCfgKey, key);
      await _initSupabase(url, key);
      if (!mounted) {
        return;
      }
      setState(() => _configured = true);
      await _afterAuth();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Falha ao conectar: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _login(String email, String password) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
      await _afterAuth();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _pretty(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _afterAuth() async {
    final SupabaseClient client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      if (mounted) {
        setState(() {
          _session = false;
          _role = null;
        });
      }
      return;
    }
    try {
      await client.rpc('admin_bootstrap');
    } on Object {
      // bootstrap é opcional (só promove o root)
    }
    Map<String, dynamic>? role;
    try {
      final Object? result = await client.rpc('admin_me');
      if (result is Map) {
        role = Map<String, dynamic>.from(result);
      }
    } on Object {
      role = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _session = true;
      _role = role;
    });
    if (role != null) {
      await Future.wait<void>(<Future<void>>[
        _loadStats(),
        _loadAdmins(),
        _loadUpdates(),
        if (_canManageGames) _loadPlatforms(),
        if (_canManageGames) _searchGames(''),
      ]);
    }
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      setState(() {
        _session = false;
        _role = null;
        _stats = null;
        _admins = <Map<String, dynamic>>[];
        _updates = <Map<String, dynamic>>[];
        _games = <Map<String, dynamic>>[];
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      final Object? result = await Supabase.instance.client.rpc('admin_stats');
      if (result is Map && mounted) {
        setState(() => _stats = Map<String, dynamic>.from(result));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _pretty(error));
      }
    }
  }

  Future<void> _loadAdmins() async {
    try {
      final Object? result = await Supabase.instance.client.rpc('admin_list');
      if (mounted) {
        setState(() {
          _admins = _rows(result);
          _adminsError = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _adminsError = _pretty(error));
      }
    }
  }

  Future<void> _loadUpdates() async {
    try {
      final Object? result = await Supabase.instance.client.rpc('admin_updates');
      if (mounted) {
        setState(() {
          _updates = _rows(result);
          _updatesError = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _updatesError = _pretty(error));
      }
    }
  }

  Future<void> _loadPlatforms() async {
    try {
      final Object? result = await Supabase.instance.client.rpc('admin_platforms');
      if (mounted) {
        setState(() => _platforms = _rows(result));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _gamesError = _pretty(error));
      }
    }
  }

  Future<void> _searchGames(String query) async {
    _gamesQuery = query;
    try {
      final Object? result = await Supabase.instance.client.rpc('admin_search_games', params: <String, dynamic>{
        'p_query': query.trim().isEmpty ? null : query.trim(),
        'p_limit': 60,
        'p_offset': 0,
      });
      if (result is Map && mounted) {
        setState(() {
          _games = _rows(result['items']);
          _gamesTotal = (result['total'] as num?)?.toInt() ?? _games.length;
          _gamesError = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _gamesError = _pretty(error));
      }
    }
  }

  Future<bool> _upsertGame(Map<String, dynamic> game) async {
    try {
      await Supabase.instance.client.rpc('admin_upsert_game', params: <String, dynamic>{
        'p_id': game['id'],
        'p_title': game['title'],
        'p_slug': game['slug'],
        'p_year': game['year'],
        'p_genre': game['genre'],
        'p_developer': game['developer'],
        'p_cover_url': game['cover_url'],
        'p_description': game['description'],
        'p_platform_slugs': game['platform_slugs'],
        'p_is_free': game['is_free'],
        'p_needs_rom': game['needs_rom'],
        'p_released_on': game['released_on'],
      });
      await _searchGames(_gamesQuery);
      return true;
    } on Object catch (error) {
      if (mounted) {
        setState(() => _gamesError = _pretty(error));
      }
      return false;
    }
  }

  Future<void> _deleteGame(String id) async {
    try {
      await Supabase.instance.client.rpc('admin_delete_game', params: <String, dynamic>{'p_id': id});
      await _searchGames(_gamesQuery);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _gamesError = _pretty(error));
      }
    }
  }

  Future<bool> _publishUpdate(String version, String message, String? url) async {
    try {
      await Supabase.instance.client.rpc('admin_publish_update', params: <String, dynamic>{
        'p_version': version,
        'p_message': message,
        'p_url': url,
      });
      await _loadUpdates();
      return true;
    } on Object catch (error) {
      if (mounted) {
        setState(() => _updatesError = _pretty(error));
      }
      return false;
    }
  }

  Future<void> _deleteUpdate(String id) async {
    try {
      await Supabase.instance.client.rpc('admin_delete_update', params: <String, dynamic>{'p_id': id});
      await _loadUpdates();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _updatesError = _pretty(error));
      }
    }
  }

  Future<bool> _grant(String email, String level, Map<String, bool> permissions) async {
    try {
      await Supabase.instance.client.rpc('admin_grant', params: <String, dynamic>{
        'p_email': email,
        'p_level': level,
        'p_permissions': permissions,
      });
      await _loadAdmins();
      return true;
    } on Object catch (error) {
      if (mounted) {
        setState(() => _adminsError = _pretty(error));
      }
      return false;
    }
  }

  Future<void> _revoke(String userId) async {
    try {
      await Supabase.instance.client.rpc('admin_revoke', params: <String, dynamic>{'p_user': userId});
      await _loadAdmins();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _adminsError = _pretty(error));
      }
    }
  }

  Future<void> _openGameForm(Map<String, dynamic>? game) async {
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _GameFormDialog(
        platforms: _platforms,
        initial: game,
      ),
    );
    if (result == null) {
      return;
    }
    final bool ok = await _upsertGame(result);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(game == null ? 'Jogo adicionado' : 'Jogo atualizado'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDeleteGame(Map<String, dynamic> game) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: _C.card,
        title: Text('Excluir "${game['title']}"?'),
        content: const Text(
          'Isso remove o jogo e tudo ligado a ele (ports, favoritos, relatos). Não dá para desfazer.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir', style: TextStyle(color: _C.danger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _deleteGame((game['id'] ?? '').toString());
    }
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is List) {
      return value.whereType<Map>().map((Map item) => Map<String, dynamic>.from(item)).toList(growable: false);
    }
    return <Map<String, dynamic>>[];
  }

  String _pretty(Object error) {
    final String text = error.toString();
    final int start = text.indexOf('{');
    if (start >= 0) {
      try {
        final Object? body = jsonDecode(text.substring(start));
        if (body is Map) {
          final Object? msg = body['msg'] ?? body['message'];
          if (msg != null) {
            return msg.toString();
          }
        }
      } on Object {
        return text;
      }
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const _Scaffold(child: Center(child: CircularProgressIndicator()));
    }
    if (!_configured) {
      return _ConfigView(error: _error, busy: _busy, onSave: _saveConfig);
    }
    if (!_session) {
      return _LoginView(error: _error, busy: _busy, onLogin: _login);
    }
    if (_role == null) {
      return _DeniedView(email: _email, onLogout: _logout);
    }

    final List<_NavSpec> nav = <_NavSpec>[
      const _NavSpec(0, Icons.insights_rounded, 'Stats'),
      if (_canManageGames) const _NavSpec(1, Icons.sports_esports_rounded, 'Jogos'),
      const _NavSpec(2, Icons.campaign_rounded, 'App'),
      const _NavSpec(3, Icons.shield_rounded, 'ADMs'),
    ];

    Widget body;
    switch (_tab) {
      case 1:
        body = _GamesView(
          games: _games,
          total: _gamesTotal,
          error: _gamesError,
          onSearch: _searchGames,
          onRefresh: () => _searchGames(_gamesQuery),
          onAdd: () => _openGameForm(null),
          onEdit: (Map<String, dynamic> game) => _openGameForm(game),
          onDelete: _confirmDeleteGame,
        );
      case 2:
        body = _UpdatesView(
          updates: _updates,
          error: _updatesError,
          isRoot: _isRoot,
          onPublish: _publishUpdate,
          onDelete: _deleteUpdate,
          onRefresh: _loadUpdates,
        );
      case 3:
        body = _AdminsView(
          role: _role!,
          admins: _admins,
          error: _adminsError,
          onGrant: _grant,
          onRevoke: _revoke,
          onRefresh: _loadAdmins,
        );
      default:
        body = _DashView(stats: _stats, onRefresh: _loadStats);
    }

    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _HeaderBar(role: _role!, email: _email, onLogout: _logout),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: _AdminNav(items: nav, index: _tab, onChanged: (int v) => setState(() => _tab = v)),
    );
  }
}

class _C {
  const _C._();
  static const Color bg = Color(0xFF07090E);
  static const Color card = Color(0xFF10141F);
  static const Color line = Color(0x1FFFFFFF);
  static const Color text = Color(0xFFF4F6FA);
  static const Color muted = Color(0x9EFFFFFF);
  static const Color faint = Color(0x6BFFFFFF);
  static const Color accent = Color(0xFF22D3EE);
  static const Color accentAlt = Color(0xFF34D399);
  static const Color danger = Color(0xFFF87171);
  static const Color warning = Color(0xFFFBBF24);
}

class _NavSpec {
  const _NavSpec(this.value, this.icon, this.label);

  final int value;
  final IconData icon;
  final String label;
}

class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: _C.bg, body: SafeArea(child: child));
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            const Color(0xFF141A28),
            _C.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.line),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.role, required this.email, required this.onLogout});

  final Map<String, dynamic> role;
  final String email;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final String level = (role['level'] ?? '').toString();
    final Color color = _crownColor(level);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[Color(0xFF0B1017), _C.bg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(bottom: BorderSide(color: _C.line)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: <Color>[_C.accent, _C.accentAlt]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.shield_rounded, color: Color(0xFF031317)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text('PORTIX ADM', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2)),
                    const SizedBox(width: 8),
                    Icon(_crownIcon(level), size: 14, color: color),
                    const SizedBox(width: 3),
                    Text(level.toUpperCase(), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
                Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _C.muted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(onPressed: onLogout, icon: const Icon(Icons.logout_rounded, color: _C.muted)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- config / login
class _ConfigView extends StatefulWidget {
  const _ConfigView({required this.onSave, this.error, this.busy = false});

  final Future<void> Function(String url, String key) onSave;
  final String? error;
  final bool busy;

  @override
  State<_ConfigView> createState() => _ConfigViewState();
}

class _ConfigViewState extends State<_ConfigView> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _key = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Scaffold(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const SizedBox(height: 24),
          const Text('PORTIX ADM', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 4)),
          const SizedBox(height: 8),
          const Text('Conecte ao projeto Supabase', style: TextStyle(color: _C.muted)),
          const SizedBox(height: 24),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Field(controller: _url, label: 'SUPABASE_URL', hint: 'https://xxxx.supabase.co'),
                const SizedBox(height: 12),
                _Field(controller: _key, label: 'SUPABASE_ANON_KEY', hint: 'eyJ...'),
                if (widget.error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(widget.error!, style: const TextStyle(color: _C.danger, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: widget.busy ? null : () => widget.onSave(_url.text.trim(), _key.text.trim()),
                  child: const Text('Salvar e conectar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView({required this.onLogin, this.error, this.busy = false});

  final Future<void> Function(String email, String password) onLogin;
  final String? error;
  final bool busy;

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pass = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Scaffold(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const SizedBox(height: 40),
          const Text('Entrar', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Use uma conta administradora.', style: TextStyle(color: _C.muted)),
          const SizedBox(height: 20),
          _Panel(
            child: Column(
              children: <Widget>[
                _Field(controller: _email, label: 'E-mail', hint: 'voce@exemplo.com'),
                const SizedBox(height: 12),
                _Field(controller: _pass, label: 'Senha', hint: '••••••', obscure: true),
                if (widget.error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(widget.error!, style: const TextStyle(color: _C.danger, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: widget.busy ? null : () => widget.onLogin(_email.text.trim(), _pass.text),
                  child: widget.busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Entrar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeniedView extends StatelessWidget {
  const _DeniedView({required this.email, required this.onLogout});

  final String email;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return _Scaffold(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.lock_rounded, size: 48, color: _C.muted),
              const SizedBox(height: 16),
              const Text('Sem acesso', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('$email não é administrador.', textAlign: TextAlign.center, style: const TextStyle(color: _C.muted)),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onLogout, child: const Text('Sair')),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- estatísticas
class _DashView extends StatelessWidget {
  const _DashView({required this.stats, required this.onRefresh});

  final Map<String, dynamic>? stats;
  final Future<void> Function() onRefresh;

  static const List<List<String>> _labels = <List<String>>[
    <String>['games', 'Jogos'],
    <String>['ports', 'Ports'],
    <String>['platforms', 'Plataformas'],
    <String>['users', 'Usuários'],
    <String>['admins', 'ADMs'],
    <String>['reviews', 'Avaliações'],
    <String>['favorites', 'Favoritos'],
    <String>['library', 'Biblioteca'],
    <String>['downloads', 'Downloads'],
  ];

  static IconData _icon(String key) {
    switch (key) {
      case 'games':
        return Icons.sports_esports_rounded;
      case 'ports':
        return Icons.extension_rounded;
      case 'platforms':
        return Icons.layers_rounded;
      case 'users':
        return Icons.group_rounded;
      case 'admins':
        return Icons.shield_rounded;
      case 'reviews':
        return Icons.star_rounded;
      case 'favorites':
        return Icons.favorite_rounded;
      case 'library':
        return Icons.video_library_rounded;
      default:
        return Icons.download_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> recent = (stats?['recent_reviews'] as List<dynamic>?) ?? <dynamic>[];
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('Visão geral', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              for (final List<String> item in _labels)
                _StatCard(label: item[1], value: (stats?[item[0]] ?? 0).toString(), icon: _icon(item[0])),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Últimas avaliações', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            const _Panel(child: Text('Sem avaliações ainda.', style: TextStyle(color: _C.muted)))
          else
            for (final dynamic item in recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RecentRow(data: Map<String, dynamic>.from(item as Map)),
              ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 158,
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: _C.accent),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _C.accent)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: _C.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final String role = (data['author_role'] ?? '').toString();
    return _Panel(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text((data['game'] ?? '—').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    if (role.isNotEmpty) ...<Widget>[
                      Icon(_crownIcon(role), size: 12, color: _crownColor(role)),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        (data['author'] ?? 'Jogador').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _C.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text('${data['rating'] ?? '—'}★', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                <String>[
                  (data['verdict'] ?? '—').toString(),
                  if (data['fps'] != null) '${data['fps']} FPS',
                ].join(' · '),
                style: const TextStyle(color: _C.muted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- jogos
class _GamesView extends StatefulWidget {
  const _GamesView({
    required this.games,
    required this.total,
    required this.onSearch,
    required this.onRefresh,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.error,
  });

  final List<Map<String, dynamic>> games;
  final int total;
  final String? error;
  final Future<void> Function(String query) onSearch;
  final Future<void> Function() onRefresh;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic> game) onEdit;
  final Future<void> Function(Map<String, dynamic> game) onDelete;

  @override
  State<_GamesView> createState() => _GamesViewState();
}

class _GamesViewState extends State<_GamesView> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _query,
                  onSubmitted: widget.onSearch,
                  onChanged: (String value) {
                    if (value.trim().isEmpty) {
                      widget.onSearch('');
                    }
                  },
                  style: const TextStyle(color: _C.text),
                  cursorColor: _C.accent,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, color: _C.faint),
                    hintText: 'Buscar por título, slug ou dev',
                    hintStyle: const TextStyle(color: _C.faint),
                    filled: true,
                    fillColor: _C.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _C.line),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: widget.onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Novo'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: <Widget>[
              Text('${widget.total} jogos', style: const TextStyle(color: _C.muted, fontSize: 12)),
              if (widget.error != null) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.error!, style: const TextStyle(color: _C.warning, fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: widget.games.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: const <Widget>[
                      _Panel(child: Text('Nenhum jogo encontrado.', style: TextStyle(color: _C.muted))),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: widget.games.length,
                    separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final Map<String, dynamic> game = widget.games[index];
                      return _GameRow(
                        game: game,
                        onEdit: () => widget.onEdit(game),
                        onDelete: () => widget.onDelete(game),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.game, required this.onEdit, required this.onDelete});

  final Map<String, dynamic> game;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String meta = <String>[
      if (game['year'] != null) game['year'].toString(),
      if ((game['genre'] ?? '').toString().isNotEmpty) game['genre'].toString(),
      if ((game['developer'] ?? '').toString().isNotEmpty) game['developer'].toString(),
    ].join(' · ');
    return _Panel(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text((game['title'] ?? '—').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _C.muted, fontSize: 12)),
                ],
                Text((game['slug'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _C.faint, fontSize: 11)),
              ],
            ),
          ),
          IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_rounded, color: _C.accent)),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded, color: _C.danger)),
        ],
      ),
    );
  }
}

class _GameFormDialog extends StatefulWidget {
  const _GameFormDialog({required this.platforms, this.initial});

  final List<Map<String, dynamic>> platforms;
  final Map<String, dynamic>? initial;

  @override
  State<_GameFormDialog> createState() => _GameFormDialogState();
}

class _GameFormDialogState extends State<_GameFormDialog> {
  late final TextEditingController _title = TextEditingController(text: _text('title'));
  late final TextEditingController _slug = TextEditingController(text: _text('slug'));
  late final TextEditingController _year = TextEditingController(text: _text('year'));
  late final TextEditingController _genre = TextEditingController(text: _text('genre'));
  late final TextEditingController _developer = TextEditingController(text: _text('developer'));
  late final TextEditingController _cover = TextEditingController(text: _text('cover_url'));
  late final TextEditingController _released = TextEditingController(text: _text('released_on'));
  late final TextEditingController _description = TextEditingController(text: _text('description'));

  late bool _isFree = widget.initial?['is_free'] == true;
  late bool _needsRom = widget.initial?['needs_rom'] == true;
  late Set<String> _selected = _initialPlatforms();

  String _text(String key) => (widget.initial?[key] ?? '').toString();

  Set<String> _initialPlatforms() {
    final Object? slugs = widget.initial?['platform_slugs'];
    if (slugs is List) {
      return slugs.map((Object? item) => item.toString()).toSet();
    }
    return <String>{};
  }

  @override
  void dispose() {
    _title.dispose();
    _slug.dispose();
    _year.dispose();
    _genre.dispose();
    _developer.dispose();
    _cover.dispose();
    _released.dispose();
    _description.dispose();
    super.dispose();
  }

  String _slugify(String value) {
    final String lower = value.toLowerCase();
    final String replaced = lower.replaceAll(RegExp('[^a-z0-9]+'), '-');
    return replaced.replaceAll(RegExp(r'(^-+)|(-+$)'), '');
  }

  void _save() {
    final String title = _title.text.trim();
    if (title.isEmpty) {
      return;
    }
    final String slug = _slug.text.trim().isEmpty ? _slugify(title) : _slug.text.trim();
    final int? year = int.tryParse(_year.text.trim());
    Navigator.of(context).pop(<String, dynamic>{
      'id': widget.initial?['id'],
      'title': title,
      'slug': slug,
      'year': year,
      'genre': _genre.text.trim(),
      'developer': _developer.text.trim(),
      'cover_url': _cover.text.trim(),
      'description': _description.text.trim(),
      'platform_slugs': _selected.toList(growable: false),
      'is_free': _isFree,
      'needs_rom': _needsRom,
      'released_on': _released.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _C.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.initial == null ? 'Novo jogo' : 'Editar jogo',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _Field(controller: _title, label: 'Título', hint: 'Super Mario 64'),
                    const SizedBox(height: 12),
                    _Field(controller: _slug, label: 'Slug (opcional)', hint: 'super-mario-64'),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(child: _Field(controller: _year, label: 'Ano', hint: '1996')),
                        const SizedBox(width: 12),
                        Expanded(child: _Field(controller: _genre, label: 'Gênero', hint: 'Plataforma')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Field(controller: _developer, label: 'Desenvolvedor', hint: 'Nintendo'),
                    const SizedBox(height: 12),
                    _Field(controller: _cover, label: 'URL da capa', hint: 'https://...'),
                    const SizedBox(height: 12),
                    _Field(controller: _released, label: 'Lançamento (AAAA-MM-DD)', hint: '1996-06-23'),
                    const SizedBox(height: 12),
                    _Field(controller: _description, label: 'Descrição', hint: 'Sobre o jogo', lines: 3),
                    const SizedBox(height: 16),
                    const Text('Plataformas', style: TextStyle(color: _C.muted, fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final Map<String, dynamic> platform in widget.platforms)
                          _PlatformChip(
                            label: (platform['name'] ?? platform['slug']).toString(),
                            selected: _selected.contains(platform['slug']),
                            onTap: () => setState(() {
                              final String slug = (platform['slug'] ?? '').toString();
                              if (!_selected.remove(slug)) {
                                _selected.add(slug);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _isFree,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Grátis'),
                      onChanged: (bool? value) => setState(() => _isFree = value ?? false),
                    ),
                    CheckboxListTile(
                      value: _needsRom,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Precisa de arquivos do jogo (ROM)'),
                      onChanged: (bool? value) => setState(() => _needsRom = value ?? false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(widget.initial == null ? 'Adicionar' : 'Salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _C.accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? _C.accent.withValues(alpha: 0.5) : _C.line),
        ),
        child: Text(
          label,
          style: TextStyle(color: selected ? _C.text : _C.muted, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- atualizações
class _UpdatesView extends StatefulWidget {
  const _UpdatesView({
    required this.updates,
    required this.isRoot,
    required this.onPublish,
    required this.onDelete,
    required this.onRefresh,
    this.error,
  });

  final List<Map<String, dynamic>> updates;
  final bool isRoot;
  final String? error;
  final Future<bool> Function(String version, String message, String? url) onPublish;
  final Future<void> Function(String id) onDelete;
  final Future<void> Function() onRefresh;

  @override
  State<_UpdatesView> createState() => _UpdatesViewState();
}

class _UpdatesViewState extends State<_UpdatesView> {
  final TextEditingController _version = TextEditingController();
  final TextEditingController _message = TextEditingController();
  final TextEditingController _url = TextEditingController();

  @override
  void dispose() {
    _version.dispose();
    _message.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final String version = _version.text.trim();
    if (version.isEmpty) {
      return;
    }
    final String? url = _url.text.trim().isEmpty ? null : _url.text.trim();
    final bool ok = await widget.onPublish(version, _message.text.trim(), url);
    if (ok && mounted) {
      _version.clear();
      _message.clear();
      _url.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Atualização v$version publicada'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('Aviso de atualização', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'O aviso aparece como diálogo no PORTIX para quem estiver em versão diferente.',
            style: TextStyle(color: _C.muted, fontSize: 12),
          ),
          if (widget.error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(widget.error!, style: const TextStyle(color: _C.warning, fontSize: 13)),
          ],
          if (widget.isRoot) ...<Widget>[
            const SizedBox(height: 16),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Field(controller: _version, label: 'Versão', hint: '1.1.0'),
                  const SizedBox(height: 12),
                  _Field(controller: _message, label: 'Mensagem', hint: 'O que mudou nesta versão', lines: 2),
                  const SizedBox(height: 12),
                  _Field(controller: _url, label: 'Link do APK (opcional)', hint: 'https://...apk'),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _publish, child: const Text('Publicar atualização')),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text('Histórico', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (widget.updates.isEmpty)
            const _Panel(child: Text('Nenhuma atualização publicada.', style: TextStyle(color: _C.muted)))
          else
            for (final Map<String, dynamic> item in widget.updates)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(Icons.campaign_rounded, size: 18, color: _C.accent),
                          const SizedBox(width: 8),
                          Text('v${item['version'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          if (item['active'] == true) const _RoleChip(level: 'ativa'),
                          if (widget.isRoot) ...<Widget>[
                            const SizedBox(width: 4),
                            TextButton(
                              onPressed: () => widget.onDelete((item['id'] ?? '').toString()),
                              child: const Text('Remover', style: TextStyle(color: _C.danger)),
                            ),
                          ],
                        ],
                      ),
                      if ((item['message'] ?? '').toString().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text((item['message']).toString(), style: const TextStyle(color: _C.muted, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- ADMs
class _AdminsView extends StatefulWidget {
  const _AdminsView({
    required this.role,
    required this.admins,
    required this.onGrant,
    required this.onRevoke,
    required this.onRefresh,
    this.error,
  });

  final Map<String, dynamic> role;
  final List<Map<String, dynamic>> admins;
  final String? error;
  final Future<bool> Function(String email, String level, Map<String, bool> permissions) onGrant;
  final Future<void> Function(String userId) onRevoke;
  final Future<void> Function() onRefresh;

  @override
  State<_AdminsView> createState() => _AdminsViewState();
}

class _AdminsViewState extends State<_AdminsView> {
  final TextEditingController _email = TextEditingController();
  String _level = 'moderator';
  final Map<String, bool> _permissions = <String, bool>{
    'view_stats': true,
    'moderate_reviews': false,
    'manage_games': false,
    'manage_users': false,
  };

  bool get _isRoot => widget.role['level'] == 'root';

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _grant() async {
    final String email = _email.text.trim();
    if (email.isEmpty) {
      return;
    }
    final bool ok = await widget.onGrant(email, _level, Map<String, bool>.from(_permissions));
    if (ok && mounted) {
      _email.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Acesso concedido a $email'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_crownIcon(widget.role['level'].toString()), size: 16, color: _crownColor(widget.role['level'].toString())),
              const SizedBox(width: 6),
              Text('Seu nível: ${widget.role['level']}', style: const TextStyle(color: _C.muted)),
            ],
          ),
          if (widget.error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(widget.error!, style: const TextStyle(color: _C.warning, fontSize: 13)),
          ],
          if (_isRoot) ...<Widget>[
            const SizedBox(height: 16),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Conceder acesso', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('A pessoa precisa ter conta no PORTIX.', style: TextStyle(color: _C.muted, fontSize: 12)),
                  const SizedBox(height: 12),
                  _Field(controller: _email, label: 'E-mail', hint: 'alguem@exemplo.com'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _level,
                    dropdownColor: _C.card,
                    decoration: const InputDecoration(labelText: 'Nível'),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: 'moderator', child: Text('Moderador')),
                      DropdownMenuItem<String>(value: 'admin', child: Text('Administrador')),
                      DropdownMenuItem<String>(value: 'root', child: Text('ADM raiz')),
                    ],
                    onChanged: (String? value) => setState(() => _level = value ?? 'moderator'),
                  ),
                  const SizedBox(height: 8),
                  for (final String key in _permissions.keys)
                    CheckboxListTile(
                      value: _permissions[key],
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_permLabel(key), style: const TextStyle(fontSize: 14)),
                      onChanged: (bool? value) => setState(() => _permissions[key] = value ?? false),
                    ),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _grant, child: const Text('Conceder')),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Administradores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (widget.admins.isEmpty)
            const _Panel(child: Text('Só o ADM raiz vê a lista completa.', style: TextStyle(color: _C.muted)))
          else
            for (final Map<String, dynamic> admin in widget.admins)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AdminRow(
                  admin: admin,
                  canRevoke: _isRoot && admin['level'] != 'root',
                  onRevoke: () => widget.onRevoke((admin['user_id'] ?? '').toString()),
                ),
              ),
        ],
      ),
    );
  }

  String _permLabel(String key) {
    switch (key) {
      case 'view_stats':
        return 'Ver estatísticas';
      case 'moderate_reviews':
        return 'Moderar avaliações';
      case 'manage_games':
        return 'Gerenciar jogos';
      case 'manage_users':
        return 'Gerenciar usuários';
      default:
        return key;
    }
  }
}

class _AdminRow extends StatelessWidget {
  const _AdminRow({required this.admin, required this.canRevoke, required this.onRevoke});

  final Map<String, dynamic> admin;
  final bool canRevoke;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final String level = (admin['level'] ?? '—').toString();
    final Map<String, dynamic> perms = admin['permissions'] is Map
        ? Map<String, dynamic>.from(admin['permissions'] as Map)
        : <String, dynamic>{};
    final String permText = level == 'root'
        ? 'todas'
        : perms.entries.where((MapEntry<String, dynamic> e) => e.value == true).map((MapEntry<String, dynamic> e) => e.key).join(', ');
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_crownIcon(level), size: 16, color: _crownColor(level)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (admin['email'] ?? admin['user_id'] ?? '—').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _RoleChip(level: level),
            ],
          ),
          if (permText.isNotEmpty && permText != '—') ...<Widget>[
            const SizedBox(height: 6),
            Text(permText, style: const TextStyle(color: _C.muted, fontSize: 12)),
          ],
          if (canRevoke) ...<Widget>[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onRevoke, child: const Text('Revogar')),
          ],
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.level});

  final String level;

  @override
  Widget build(BuildContext context) {
    final Color color = _crownColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(level, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

IconData _crownIcon(String level) {
  switch (level) {
    case 'root':
      return Icons.workspace_premium_rounded;
    case 'admin':
      return Icons.military_tech_rounded;
    case 'moderator':
      return Icons.verified_rounded;
    default:
      return Icons.person_rounded;
  }
}

Color _crownColor(String level) {
  switch (level) {
    case 'root':
      return _C.warning;
    case 'admin':
      return _C.accent;
    case 'moderator':
      return _C.accentAlt;
    default:
      return _C.muted;
  }
}

class _AdminNav extends StatelessWidget {
  const _AdminNav({required this.items, required this.index, required this.onChanged});

  final List<_NavSpec> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 60,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _C.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _C.line),
          ),
          child: Row(
            children: <Widget>[
              for (final _NavSpec item in items) _navButton(item),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navButton(_NavSpec item) {
    final bool active = index == item.value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(item.value),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _C.accent.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(item.icon, size: 17, color: active ? _C.accent : _C.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: active ? _C.text : _C.muted, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.lines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      maxLines: lines,
      minLines: 1,
      style: const TextStyle(color: _C.text),
      cursorColor: _C.accent,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
