import 'package:flutter_test/flutter_test.dart';

import 'package:OpenView2/boards/board_registry.dart';

void main() {
  test('Board registry exposes the expected phase-1 boards', () {
    final ids = BoardRegistry.all.map((b) => b.id).toSet();
    expect(ids, containsAll({'sensything_ox', 'sensything_cap', 'ads1292r', 'max30003'}));
  });

  test('Every descriptor declares at least one packet decoder', () {
    for (final b in BoardRegistry.all) {
      expect(b.packets, isNotEmpty, reason: '${b.id} has no packets');
      expect(
        b.channels.isNotEmpty || b.matrices.isNotEmpty,
        isTrue,
        reason: '${b.id} declares neither channels nor matrices',
      );
    }
  });
}
