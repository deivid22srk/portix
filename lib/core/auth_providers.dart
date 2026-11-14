import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'env.dart';

/// Quais provedores externos estão habilitados no projeto Supabase
/// (lê `/auth/v1/settings`). Usado para não oferecer um botão que vai falhar.
final enabledProvidersProvider = FutureProvider<Set<String>>((ref) async {
  if (!Env.isConfigured) {
    return const <String>{};
  }
  try {
    final http.Response response = await http.get(
      Uri.parse('${Env.supabaseUrl}/auth/v1/settings'),
      headers: <String, String>{'apikey': Env.supabaseAnonKey},
    );
    if (response.statusCode != 200) {
      return const <String>{};
    }
    final Object? body = jsonDecode(response.body);
    if (body is! Map) {
      return const <String>{};
    }
    final Object? external = body['external'];
    if (external is! Map) {
      return const <String>{};
    }
    return external.entries
        .where((MapEntry<Object?, Object?> entry) => entry.value == true)
        .map((MapEntry<Object?, Object?> entry) => entry.key.toString())
        .toSet();
  } on Object {
    return const <String>{};
  }
});
