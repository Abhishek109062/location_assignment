import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_tracker/app/app.dart';
import 'package:location_tracker/data/datasources/local/location_database.dart';
import 'package:location_tracker/presentation/providers/tracking_providers.dart';
import 'package:location_tracker/services/connectivity_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeConnectivity extends Mock implements ConnectivityService {}

void main() {
  late Directory tempDir;
  late _FakeConnectivity connectivity;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('widget_smoke_');
    connectivity = _FakeConnectivity();
    when(() => connectivity.isOnline).thenReturn(true);
    when(() => connectivity.forceOffline).thenReturn(false);
    when(() => connectivity.start()).thenAnswer((_) async {});
    when(() => connectivity.dispose()).thenAnswer((_) async {});
    when(() => connectivity.onStatusChanged)
        .thenAnswer((_) => const Stream<bool>.empty());
    when(() => connectivity.setForceOffline(any())).thenReturn(null);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('home screen renders core controls', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationDatabaseProvider.overrideWithValue(
            LocationDatabase(
              databaseFactory: databaseFactoryFfi,
              databasePath: '${tempDir.path}/widget.db',
            ),
          ),
          connectivityServiceProvider.overrideWithValue(connectivity),
        ],
        child: const LocationTrackerApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Location Tracker'), findsOneWidget);
    expect(find.text('Start tracking'), findsOneWidget);
    expect(find.text('Force offline'), findsOneWidget);
  });
}
