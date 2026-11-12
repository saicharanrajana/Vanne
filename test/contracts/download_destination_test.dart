import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:system_wallpaper/system_wallpaper.dart';
import 'package:vanne/core/downloads/download_destination.dart';
import 'package:vanne/core/downloads/download_destination_controller.dart';
import 'package:vanne/core/storage/settings_store.dart';

import '../support/fake_platform.dart';

/// Contract tests for the download-folder grant lifecycle.
///
/// These are the interleavings a widget journey cannot drive reliably:
/// concurrent picks, a save that outlives a folder change, revoked grants and
/// grants that must NOT be released. Each case names the user-visible
/// outcome it protects.
void main() {
  late Directory dir;
  late SettingsStore store;
  late FakeDownloadStoragePlatform platform;
  late DownloadDestinationController controller;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vanne_grant_');
    Hive.init(dir.path);
    store = SettingsStore();
    await store.open();
    platform = FakeDownloadStoragePlatform();
    controller = DownloadDestinationController(store, platform: platform);
  });

  tearDown(() async {
    controller.dispose();
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  group('restore', () {
    test('with no stored grant keeps the default folder', () async {
      await controller.restore();

      expect(controller.destination.value, isA<DefaultDownloadDestination>());
      expect(controller.access.value, DestinationAccess.available);
      expect(platform.checkedParents, isEmpty);
    });

    test('re-validates a stored grant and adopts a renamed label', () async {
      await store.setDownloadDestination(
        treeUri: 'content://tree/a',
        parentLabel: 'Old name',
      );
      platform.checkResult = const ParentAccessAvailable('New name');

      await controller.restore();

      final destination = controller.destination.value;
      expect(destination, isA<ChosenDownloadDestination>());
      destination as ChosenDownloadDestination;
      expect(destination.treeUri, 'content://tree/a');
      expect(destination.parentLabel, 'New name');
      expect(controller.access.value, DestinationAccess.available);
    });

    test('a revoked grant surfaces as lost instead of silently resetting', () async {
      await store.setDownloadDestination(
        treeUri: 'content://tree/a',
        parentLabel: 'A',
      );
      platform.checkResult = const ParentAccessLost();

      await controller.restore();

      expect(controller.access.value, DestinationAccess.lost);
      expect(
        controller.destination.value.treeUri,
        'content://tree/a',
        reason: 'the destination is kept so Settings can offer "choose again"',
      );
    });

    test('an unverifiable grant stays usable', () async {
      await store.setDownloadDestination(
        treeUri: 'content://tree/a',
        parentLabel: 'A',
      );
      platform.checkResult = const ParentAccessUnknown('provider error');

      await controller.restore();

      expect(controller.access.value, DestinationAccess.available);
    });
  });

  group('chooseParent', () {
    test('persists the picked folder for the next launch', () async {
      platform.pickResults
        ..clear()
        ..add(const ParentPicked(treeUri: 'content://tree/a', label: 'A'));

      final outcome = await controller.chooseParent();

      expect(outcome, DestinationPickOutcome.picked);
      expect(controller.destination.value.treeUri, 'content://tree/a');
      expect(store.downloadTreeUri, 'content://tree/a');
      expect(store.downloadParentLabel, 'A');
    });

    test('cancelling leaves the previous destination untouched', () async {
      platform.pickResults
        ..clear()
        ..add(const ParentPicked(treeUri: 'content://tree/a', label: 'A'));
      await controller.chooseParent();

      platform.pickResults
        ..clear()
        ..add(const ParentPickCanceled());
      final outcome = await controller.chooseParent();

      expect(outcome, DestinationPickOutcome.canceled);
      expect(controller.destination.value.treeUri, 'content://tree/a');
      expect(store.downloadTreeUri, 'content://tree/a');
    });

    test('a picker failure is reported without changing the folder', () async {
      platform.pickResults
        ..clear()
        ..add(const ParentPickFailure('noActivity', 'No picker available'));

      final outcome = await controller.chooseParent();

      expect(outcome, DestinationPickOutcome.failed);
      expect(controller.error.value, 'No picker available');
      expect(controller.destination.value, isA<DefaultDownloadDestination>());
    });

    test('a concurrent pick returns busy and never overwrites the first', () async {
      final pick = Completer<ParentPickResult>();
      platform.pendingPick = pick.future;

      final first = controller.chooseParent();
      expect(controller.picking.value, isTrue);

      final second = await controller.chooseParent();
      expect(second, DestinationPickOutcome.busy);
      expect(
        platform.pickedParents,
        hasLength(1),
        reason: 'the second attempt never opens a picker',
      );

      pick.complete(const ParentPicked(treeUri: 'content://tree/a', label: 'A'));
      expect(await first, DestinationPickOutcome.picked);
      expect(controller.destination.value.treeUri, 'content://tree/a');
    });
  });

  group('grant release', () {
    test('picking a new folder releases the previous one', () async {
      platform.pickResults
        ..clear()
        ..add(const ParentPicked(treeUri: 'content://tree/a', label: 'A'))
        ..add(const ParentPicked(treeUri: 'content://tree/b', label: 'B'));

      await controller.chooseParent();
      await controller.chooseParent();

      expect(platform.releasedParents, ['content://tree/a']);
    });

    test('re-selecting a queued folder keeps its grant', () async {
      // A save holds the release open, so A is queued while B becomes live.
      controller.beginSave();
      platform.pickResults
        ..clear()
        ..add(const ParentPicked(treeUri: 'content://tree/a', label: 'A'))
        ..add(const ParentPicked(treeUri: 'content://tree/b', label: 'B'))
        ..add(const ParentPicked(treeUri: 'content://tree/a', label: 'A'));

      await controller.chooseParent(); // A live
      await controller.chooseParent(); // B live, A queued
      await controller.chooseParent(); // A live again

      controller.endSave();

      expect(
        platform.releasedParents,
        isNot(contains('content://tree/a')),
        reason: 'the live folder must keep its grant',
      );
      expect(platform.releasedParents, contains('content://tree/b'));
    });

    test('releases are deferred until the in-flight save finishes', () async {
      platform.pickResults
        ..clear()
        ..add(const ParentPicked(treeUri: 'content://tree/a', label: 'A'));

      await controller.chooseParent();
      controller.beginSave();

      await controller.resetToDefault();
      expect(
        platform.releasedParents,
        isEmpty,
        reason: 'a save is still writing into the old folder',
      );

      controller.endSave();
      expect(platform.releasedParents, ['content://tree/a']);
    });

    test('resetting to default clears the persisted grant', () async {
      platform.pickResults
        ..clear()
        ..add(const ParentPicked(treeUri: 'content://tree/a', label: 'A'));
      await controller.chooseParent();

      await controller.resetToDefault();

      expect(controller.destination.value, isA<DefaultDownloadDestination>());
      expect(store.downloadTreeUri, isNull);
      expect(store.downloadParentLabel, isNull);
    });

    test('a stale failure does not accuse the current folder', () async {
      platform.pickResults
        ..clear()
        ..add(const ParentPicked(treeUri: 'content://tree/b', label: 'B'));
      await controller.chooseParent();

      controller.markAccessLost('content://tree/a');

      expect(controller.access.value, DestinationAccess.available);
    });
  });
}
