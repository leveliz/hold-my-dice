/// A player in any helper (Pocket Banker, Score Snitch, ...).
class Player {
  const Player({required this.id, required this.name, required this.color});

  factory Player.fromJson(Map<String, dynamic> json) => Player(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as int,
  );

  final String id;
  final String name;

  /// ARGB value, kept as an int so the domain layer stays free of Flutter.
  final int color;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};
}

/// A player's name and colour as remembered from the last game.
class PlayerSetting {
  const PlayerSetting({required this.name, required this.color});

  factory PlayerSetting.fromJson(Map<String, dynamic> json) =>
      PlayerSetting(name: json['name'] as String, color: json['color'] as int);

  final String name;
  final int color;

  Map<String, dynamic> toJson() => {'name': name, 'color': color};
}
