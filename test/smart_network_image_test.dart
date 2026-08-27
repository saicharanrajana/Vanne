import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:wallpaper_app/app/theme/app_theme.dart';
import 'package:wallpaper_app/shared/widgets/smart_network_image.dart';

Widget _host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    theme: AppTheme.build(brightness: Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: SizedBox.expand(child: child)),
    ),
  );
}

Finder _image(String url) => find.byWidgetPredicate(
  (widget) => widget is CachedNetworkImage && widget.imageUrl == url,
);

void main() {
  testWidgets('uses a cached thumbnail while the full image loads', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        _host(
          const SmartNetworkImage(
            'https://example.test/full.jpg',
            placeholderImageUrl: 'https://example.test/thumb.jpg',
          ),
        ),
      );

      final fullFinder = _image('https://example.test/full.jpg');
      expect(fullFinder, findsOneWidget);
      expect(_image('https://example.test/thumb.jpg'), findsOneWidget);
      final fullImage = tester.widget<CachedNetworkImage>(fullFinder);
      final placeholder = fullImage.placeholder!(
        tester.element(fullFinder),
        fullImage.imageUrl,
      );

      expect(placeholder, isA<SizedBox>());
    });
  });

  testWidgets('falls back without recursively loading the primary URL', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        _host(
          const SmartNetworkImage(
            'https://example.test/full.jpg',
            placeholderImageUrl: 'https://example.test/full.jpg',
          ),
        ),
      );

      final fullFinder = _image('https://example.test/full.jpg');
      final fullImage = tester.widget<CachedNetworkImage>(fullFinder);
      expect(
        fullImage.placeholder!(tester.element(fullFinder), fullImage.imageUrl),
        isNot(isA<SizedBox>()),
      );
    });
  });

  testWidgets('disables both image fades when reduced motion is requested', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        _host(
          const SmartNetworkImage(
            'https://example.test/full.jpg',
            placeholderImageUrl: 'https://example.test/thumb.jpg',
          ),
          disableAnimations: true,
        ),
      );

      final fullImage = tester.widget<CachedNetworkImage>(
        _image('https://example.test/full.jpg'),
      );
      expect(fullImage.fadeInDuration, Duration.zero);
      expect(fullImage.fadeOutDuration, Duration.zero);

      final thumbnail = tester.widget<CachedNetworkImage>(
        _image('https://example.test/thumb.jpg'),
      );
      expect(thumbnail.fadeInDuration, Duration.zero);
      expect(thumbnail.fadeOutDuration, Duration.zero);
    });
  });
}
