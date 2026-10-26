/// One line of the final ranking of a game.
class Standing {
  const Standing({
    required this.seat,
    required this.rank,
    required this.balance,
    required this.out,
  });

  final String seat;

  /// 1 for the winner; players with the same money share a rank and the next
  /// rank skips (1, 2, 2, 4).
  final int rank;
  final int balance;

  /// The player went bankrupt.
  final bool out;
}

/// The ranking at the end of a game: the players still in, by what they hold
/// (most first, the same money in seat order), then those who went out, the
/// one who left last first. The bank is not a player.
List<Standing> standings({
  required List<String> seats,
  required Map<String, int> balances,
  required List<String> bankrupt,
}) {
  final still = [
    for (final s in seats)
      if (!bankrupt.contains(s)) s,
  ];
  // A stable sort: equal money keeps the order of the seats.
  final indexed = [for (var i = 0; i < still.length; i++) (i, still[i])];
  indexed.sort((a, b) {
    final byMoney = (balances[b.$2] ?? 0).compareTo(balances[a.$2] ?? 0);
    return byMoney != 0 ? byMoney : a.$1.compareTo(b.$1);
  });
  final result = <Standing>[];
  for (var i = 0; i < indexed.length; i++) {
    final seat = indexed[i].$2;
    final money = balances[seat] ?? 0;
    final tied = i > 0 && (balances[indexed[i - 1].$2] ?? 0) == money;
    result.add(
      Standing(
        seat: seat,
        rank: tied ? result[i - 1].rank : i + 1,
        balance: money,
        out: false,
      ),
    );
  }
  final left = bankrupt.reversed.where(seats.contains).toList();
  for (var i = 0; i < left.length; i++) {
    result.add(
      Standing(
        seat: left[i],
        rank: indexed.length + i + 1,
        balance: balances[left[i]] ?? 0,
        out: true,
      ),
    );
  }
  return result;
}
