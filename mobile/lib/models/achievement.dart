import '../core/avatar_sizes.dart';
import '../core/time_json.dart';

class Achievement {
  final int id;
  final String name;
  final String description;
  final String category;
  final String logo;
  final Map<String, String>? logoSizes;
  final DateTime? acquiredAt;
  final String? modelUrl;

  const Achievement({required this.id, required this.name, required this.description, required this.category, required this.logo, this.logoSizes, this.acquiredAt, this.modelUrl});

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
    id: json['id'] as int,
    name: json['name'] as String,
    description: json['description'] as String,
    category: json['category'] as String,
    logo: json['logo'] as String,
    logoSizes: parseAvatarSizes(json['logo_sizes']),
    acquiredAt: json['acquired_at'] == null ? null : parseUtcLocal(json['acquired_at']),
    modelUrl: json['model_url'] as String?,
  );
}
