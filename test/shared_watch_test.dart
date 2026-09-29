import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/models.dart';
import 'package:ibasho/backend/shared_watch.dart';

void main() {
  test(
    'una conexión por ruta, con repetición al que llega tarde y cierre al final',
    () async {
      final shared = SharedWatches();
      var opened = 0;
      var cancelled = 0;
      late StreamController<DatabaseEvent> src;
      Stream<DatabaseEvent> source() {
        opened++;
        src = StreamController<DatabaseEvent>(onCancel: () => cancelled++);
        return src.stream;
      }

      final a = <DatabaseEvent>[];
      final b = <DatabaseEvent>[];
      final subA = shared.watch('/x', source).listen(a.add);
      src.add(const DatabaseEvent(path: '/', data: {'n': 1}, isPatch: false));
      await pumpEventQueue();
      final subB = shared.watch('/x', source).listen(b.add);
      await pumpEventQueue();
      expect(opened, 1);
      expect(b.single.data, {'n': 1});

      await subA.cancel();
      expect(cancelled, 0);
      await subB.cancel();
      expect(cancelled, 1);
      expect(shared.open, 0);
    },
  );
}
