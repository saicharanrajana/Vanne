import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens external URLs (Wallhaven pages) in an in-app browser.
///
/// Wrapped so screens don't touch the plugin and tests can fake it.
final class UrlLauncherService {
  final Future<bool> Function(Uri) _launch;

  UrlLauncherService({Future<bool> Function(Uri)? launch})
    : _launch = launch ?? _launchUrl;

  static Future<bool> _launchUrl(Uri url) {
    return launchUrl(
      url,
      mode: LaunchMode.inAppBrowserView,
      browserConfiguration: const BrowserConfiguration(showTitle: true),
      webViewConfiguration: const WebViewConfiguration(
        enableJavaScript: true,
        enableDomStorage: true,
      ),
    );
  }

  /// Launches [url] in an in-app browser (Custom Tabs / SFSafariViewController);
  /// returns `false` when no handler is available. This keeps Wallhaven
  /// pages inside the app *with* the system browser's toolbar — back,
  /// share, open-in-browser, title — unlike a raw `inAppWebView`.
  Future<bool> openInApp(Uri url) async {
    try {
      return await _launch(url);
    } on PlatformException {
      // canLaunchUrl can report false when Android package visibility is
      // restricted even though launchUrl can still open the URL.
      return false;
    }
  }
}
