import 'package:url_launcher/url_launcher.dart';

/// Opens external URLs (Wallhaven pages) in an in-app browser.
///
/// Wrapped so screens don't touch the plugin and tests can fake it.
final class UrlLauncherService {
  /// Launches [url] in an in-app browser (Custom Tabs / SFSafariViewController);
  /// returns `false` when no handler is available. This keeps Wallhaven
  /// pages inside the app *with* the system browser's toolbar — back,
  /// share, open-in-browser, title — unlike a raw `inAppWebView`.
  Future<bool> openInApp(Uri url) async {
    if (await canLaunchUrl(url)) {
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
    return false;
  }

}

