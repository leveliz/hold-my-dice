class Player {
  const Player({required this.id, required this.name, required this.color});

  final String id;
  final String name;

  /// ARGB value, kept as an int so the domain layer stays free of Flutter.
  final int color;
}
