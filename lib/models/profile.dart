import 'parsing.dart';

/// Perfil do usuário (conta real). Capa de perfil é opcional.
class UserProfile {
  const UserProfile({
    required this.id,
    this.displayName = 'Jogador',
    this.coverUrl,
    this.handle,
  });

  final String id;
  final String displayName;
  final String? coverUrl;
  final String? handle;

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
        id: asTextOr(map['id'], ''),
        displayName: asTextOr(map['display_name'], 'Jogador'),
        coverUrl: asText(map['cover_url']),
        handle: asText(map['handle']),
      );
}
