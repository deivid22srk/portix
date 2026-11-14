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
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _C.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _C.accent,
      secondary: _C.accentAlt,
      surface: _C.bg,
      error: _C.danger,
    );
    return MaterialApp(
      title: 'PORTIX ADM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: scheme,
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
  int _tab = 0;
  String? _error;
  String? _adminsError;
  Map<String, dynamic>? _role;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _admins = <Map<String, dynamic>>[];
  bool _busy = false;

  String get _email => Supabase.instance.client.auth.currentUser?.email ?? '';

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
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
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
    final User? user = client.auth.currentUser;
    if (user == null) {
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
      await Future.wait<void>(<Future<void>>[_loadStats(), _loadAdmins()]);
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
      final List<Map<String, dynamic>> rows = result is List
          ? result
              .whereType<Map>()
              .map((Map item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _admins = rows;
          _adminsError = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _adminsError = _pretty(error));
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
      await Supabase.instance.client.rpc('admin_revoke', params: <String, dynamic>{
        'p_user': userId,
      });
      await _loadAdmins();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _adminsError = _pretty(error));
      }
    }
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
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('PORTIX ADM · ${_role!['level']}'),
        actions: <Widget>[
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      body: _tab == 0 ? _DashView(stats: _stats, onRefresh: _loadStats) : _AdminsView(
        role: _role!,
        admins: _admins,
        error: _adminsError,
        email: _email,
        onGrant: _grant,
        onRevoke: _revoke,
        onRefresh: _loadAdmins,
      ),
      bottomNavigationBar: _AdminNav(
        index: _tab,
        onChanged: (int value) => setState(() => _tab = value),
      ),
    );
  }
}

class _C {
  const _C._();
  static const Color bg = Color(0xFF07090E);
  static const Color card = Color(0xFF101220);
  static const Color line = Color(0x1FFFFFFF);
  static const Color text = Color(0xFFF4F6FA);
  static const Color muted = Color(0x9EFFFFFF);
  static const Color accent = Color(0xFF22D3EE);
  static const Color accentAlt = Color(0xFF34D399);
  static const Color danger = Color(0xFFF87171);
  static const Color warning = Color(0xFFFBBF24);
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
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.line),
      ),
      child: child,
    );
  }
}

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
                  onPressed: widget.busy
                      ? null
                      : () => widget.onSave(_url.text.trim(), _key.text.trim()),
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
                  onPressed: widget.busy
                      ? null
                      : () => widget.onLogin(_email.text.trim(), _pass.text),
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

  @override
  Widget build(BuildContext context) {
    final List<dynamic> recent = (stats?['recent_reviews'] as List<dynamic>?) ?? <dynamic>[];
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              for (final List<String> item in _labels)
                _StatCard(label: item[1], value: (stats?[item[0]] ?? 0).toString()),
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
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: _C.accent)),
            const SizedBox(height: 4),
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
                Text(
                  <String>[
                    (data['author'] ?? 'Jogador').toString(),
                    if (role.isNotEmpty) '(${role.toUpperCase()})',
                  ].join(' '),
                  style: const TextStyle(color: _C.muted, fontSize: 12),
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

class _AdminsView extends StatefulWidget {
  const _AdminsView({
    required this.role,
    required this.admins,
    required this.email,
    required this.onGrant,
    required this.onRevoke,
    required this.onRefresh,
    this.error,
  });

  final Map<String, dynamic> role;
  final List<Map<String, dynamic>> admins;
  final String email;
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
          Text('Nível atual: ${widget.role['level']}', style: const TextStyle(color: _C.muted)),
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
              Expanded(
                child: Text(
                  (admin['email'] ?? admin['user_id'] ?? '—').toString(),
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
            OutlinedButton(
              onPressed: onRevoke,
              child: const Text('Revogar'),
            ),
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
    final Color color = switch (level) {
      'root' => _C.warning,
      'admin' => _C.accent,
      _ => _C.muted,
    };
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

class _AdminNav extends StatelessWidget {
  const _AdminNav({required this.index, required this.onChanged});

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
              _navButton(context, 0, Icons.insights_rounded, 'Estatísticas'),
              _navButton(context, 1, Icons.shield_rounded, 'ADMs'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navButton(BuildContext context, int value, IconData icon, String label) {
    final bool active = index == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _C.accent.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 18, color: active ? _C.accent : _C.muted),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: active ? _C.text : _C.muted, fontWeight: FontWeight.w600)),
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
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
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
