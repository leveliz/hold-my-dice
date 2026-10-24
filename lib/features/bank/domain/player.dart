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
