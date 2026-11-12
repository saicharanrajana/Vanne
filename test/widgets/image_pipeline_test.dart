import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/shared/widgets/smart_network_image.dart';

/// The image boundary decides how much RAM a feed costs and whether a tile
/// flashes. These tests pin the contract the grids rely on.
Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: AppTheme.build(brightness: Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox.expand(child: child),
    ),
  ),
);

Finder _image(String url) => find.byWidgetPredicate(
  (widget) => widget is CachedNetworkImage && widget.imageUrl == url,
);

void main() {
  testWidgets('thumbnail stays under the full image while it loads', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        _host(
          const SmartNetworkImage(
            'https://example.test/full.jpg',
            placeholderImageUrl: 'https://example.test/thumb.jpg',
            memCacheWidth: 400,
          ),
        ),
      );

      expect(_image('https://example.test/full.jpg'), findsOneWidget);
      expect(_image('https://example.test/thumb.jpg'), findsOneWidget);
      // Both images decode at cell resolution, not full photo resolution.
      expect(
        tester
            .widgetList<CachedNetworkImage>(_image('https://example.test/full.jpg'))
            .single
            .memCacheWidth,
        400,
      );
    });
  });

  testWidgets('a self-referential thumbnail never loads twice', (tester) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        _host(
          const SmartNetworkImage(
            'https://example.test/full.jpg',
            placeholderImageUrl: 'https://example.test/full.jpg',
          ),
        ),
      );

      expect(_image('https://example.test/full.jpg'), findsOneWidget);
    });
  });

  testWidgets('an empty url falls back without any network request', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(_host(const SmartNetworkImage('')));

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byType(Icon), findsOneWidget);
    });
  });

  testWidgets('reduced motion removes the cross-fade', (tester) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        _host(const SmartNetworkImage('https://example.test/full.jpg'), disableAnimations: true),
      );

      final image = tester.widget<CachedNetworkImage>(
        _image('https://example.test/full.jpg'),
      );
      expect(image.fadeInDuration, Duration.zero);
      expect(image.fadeOutDuration, Duration.zero);
    });
  });
}
