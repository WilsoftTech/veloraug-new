import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/api/account_api.dart';
import 'package:veloraug/api/catalogue_api.dart';
import 'package:veloraug/api/playback_api.dart';
import 'package:veloraug/app.dart';
import 'package:veloraug/auth/auth_controller.dart';
import 'package:veloraug/auth/oauth_client.dart';
import 'package:veloraug/auth/oauth_config.dart';
import 'package:veloraug/auth/token_store.dart';
import 'package:veloraug/downloads/downloads.dart';
import 'package:veloraug/l10n/app_localizations.dart';
import 'package:veloraug/l10n/app_localizations_en.dart';
import 'package:veloraug/notifications/push_status.dart';
import 'package:veloraug/screens/account/account_pages.dart';
import 'package:veloraug/screens/account/danger_zone_screen.dart';
import 'package:veloraug/screens/account/history_screen.dart';
import 'package:veloraug/screens/account/notifications_screen.dart';
import 'package:veloraug/screens/browse_screen.dart';
import 'package:veloraug/security/app_lock.dart';
import 'package:veloraug/theme/velora_theme.dart';
import 'package:veloraug/widgets/edition_cards.dart';
import 'package:veloraug/widgets/poster_grid.dart';
import 'package:veloraug/widgets/startup_gate.dart';

import 'downloads/download_fakes.dart' as fakes;
import 'support.dart';

/// Editions [count] long, each in [genres].
FakeApi titled(int count, {List<String> genres = const ['Action']}) {
  final api = FakeApi();
  for (var i = 0; i < count; i++) {
    api.editions.add({
      ...card(
        'f$i',
        title: 'Film $i',
        kind: i.isEven ? 'movie' : 'series',
        vj: i % 3 == 0 ? 'VJ Junior' : 'VJ Emmy',
      ),
      'genres': genres,
    });
  }
  return api;
}

Future<void> openRow(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

/// The phone App lock prompt, answering what each test sets.
class FakeLock implements LockAuthenticator {
  FakeLock({this.supported = true});

  bool supported;
  final answers = <LockCheck>[];
  int checks = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<LockCheck> check(String reason) async {
    checks++;
    return answers.isEmpty ? LockCheck.passed : answers.removeAt(0);
  }
}

const _issuer = 'https://auth.example.test/neondb/auth';
const _callback = 'https://pages.example.test/auth/callback/android';

String jwt(Map<String, Object?> payload) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'EdDSA'})}.${part(payload)}.signature';
}

/// Signed in as [first]; every later sign-in, such as the one deleting asks
/// for, comes back as the next of [later].
class OAuthFake {
  OAuthFake({required String first, this.later = const []})
    : store = MemoryTokenStore(
        StoredSession(
          accessToken: jwt({'sub': first}),
          refreshToken: 'R0',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          email: '$first@example.test',
        ),
      );

  final MemoryTokenStore store;
  final List<String> later;
  final authorizeUrls = <Uri>[];
  final revoked = <String>[];
  String? _nonce;
  int _signIns = 0;

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('oauth-authorization-server')) {
      return http.Response(
        jsonEncode({
          'issuer': _issuer,
          'authorization_endpoint': '$_issuer/oauth2/authorize',
          'token_endpoint': '$_issuer/oauth2/token',
          'revocation_endpoint': '$_issuer/oauth2/revoke',
        }),
        200,
      );
    }
    if (path.endsWith('/oauth2/token')) {
      final who = later[_signIns++];
      return http.Response(
        jsonEncode({
          'access_token': jwt({'sub': who}),
          'refresh_token': 'R-$who',
          'expires_in': 3600,
          'id_token': jwt({'nonce': _nonce, 'email': '$who@example.test'}),
        }),
        200,
      );
    }
    if (path.endsWith('/oauth2/revoke')) {
      revoked.add(request.bodyFields['token']!);
      return http.Response('', 200);
    }
    return http.Response('', 404);
  });

  late final auth = AuthController(
    client: OAuthClient(
      config: OAuthConfig(
        issuer: _issuer,
        clientId: 'client-1',
        resource: 'https://api.example.test',
        redirectUri: Uri.parse(_callback),
        signOutPage: Uri.parse('https://pages.example.test/sign-out'),
      ),
      httpClient: client,
      browserStep: (url, _) async {
        if (url.path == '/sign-out') return '$_callback?signed_out=1';
        authorizeUrls.add(url);
        _nonce = url.queryParameters['nonce'];
        return '$_callback?code=c&state=${url.queryParameters['state']}';
      },
    ),
    store: store,
  );
}

/// One account page on its own, with the app's scopes.
Future<void> pumpPage(
  WidgetTester tester, {
  required AuthController auth,
  required FakeApi api,
  required AccountPage Function(BuildContext) page,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(500, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AuthScope(
      controller: auth,
      child: CatalogueScope(
        api: api.catalogue(),
        child: PlaybackScope(
          api: api.playback(auth),
          child: MaterialApp(
            theme: buildVeloraTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => AccountPage.open(context, page(context)),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  final l = AppLocalizationsEn();

  // --- The shared poster grid -------------------------------------------------

  group('poster grid', () {
    test(
      'three columns on a 360 px phone, two when narrow or text is large',
      () {
        // A 360 px phone has 16 px gutters, so the grid is 328 px wide.
        expect(
          PosterGridLayout.resolve(width: 328, screenWidth: 360).columns,
          3,
        );
        expect(
          PosterGridLayout.resolve(width: 380, screenWidth: 412).columns,
          3,
        );
        expect(
          PosterGridLayout.resolve(width: 288, screenWidth: 320).columns,
          2,
        );
        expect(
          PosterGridLayout.resolve(
            width: 328,
            screenWidth: 360,
            textScale: 1.5,
          ).columns,
          2,
        );
        expect(
          PosterGridLayout.resolve(width: 600, screenWidth: 768).columns,
          greaterThanOrEqualTo(3),
        );
        expect(
          PosterGridLayout.resolve(width: 1184, screenWidth: 1280).columns,
          6,
        );
      },
    );

    testWidgets('Search shows three posters a row at 360 px, six in view', (
      tester,
    ) async {
      final api = titled(12);
      await pumpApp(tester, api, size: const Size(360, 780));
      await goTo(tester, 'Search');
      await tester.enterText(find.byType(TextField), 'film');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      // Scroll the results to the top of the screen, as a viewer would.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pumpAndSettle();

      final tiles = find.byType(EditionTile);
      expect(tiles, findsNWidgets(12));
      final first = tester.getRect(tiles.at(0));
      final third = tester.getRect(tiles.at(2));
      final fourth = tester.getRect(tiles.at(3));
      expect(third.top, first.top);
      expect(fourth.top, greaterThan(first.bottom));
      expect(first.width, greaterThan(96));
      // Two whole rows fit on screen at once.
      expect(fourth.height * 2, lessThan(780 - 80 - 56));
      expect(tester.takeException(), isNull);
    });

    testWidgets('large text falls back to two columns without clipping', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = titled(6);
      await pumpApp(tester, api, size: const Size(360, 780));
      await goTo(tester, 'Search');
      await tester.enterText(find.byType(TextField), 'film');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      final tiles = find.byType(EditionTile);
      expect(tester.getRect(tiles.at(1)).top, tester.getRect(tiles.at(0)).top);
      expect(
        tester.getRect(tiles.at(2)).top,
        greaterThan(tester.getRect(tiles.at(0)).top),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // --- Filter -----------------------------------------------------------------

  group('Filter', () {
    FakeApi filterable() {
      final api = FakeApi()
        ..vjs.addAll([
          {
            'id': 'v1',
            'name': 'VJ Junior',
            'slug': 'vj-junior',
            'editions': 30,
          },
          {'id': 'v2', 'name': 'VJ Emmy', 'slug': 'vj-emmy', 'editions': 1},
        ])
        ..genres = [
          {'name': 'Action', 'editions': 30},
          {'name': 'Comedy', 'editions': 1},
        ];
      for (var i = 0; i < 30; i++) {
        api.editions.add({
          ...card('a$i', title: 'Action $i', vj: 'VJ Junior'),
          'genres': ['Action'],
        });
      }
      api.editions.add({
        ...card('c1', title: 'Laugh', vj: 'VJ Emmy', kind: 'series'),
        'genres': ['Comedy'],
      });
      return api;
    }

    testWidgets('combines type, genre and VJ on the server, a page at a time', (
      tester,
    ) async {
      final api = filterable();
      await pumpApp(tester, api, size: const Size(400, 1600));
      await goTo(tester, 'Filter');

      await tester.tap(find.text('Movies').last);
      await tester.tap(find.byKey(const ValueKey('choice-Action')));
      await tester.tap(find.byKey(const ValueKey('choice-vj-junior')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      expect(find.byType(BrowseScreen), findsOneWidget);
      final asked = api.requests.last.url.queryParameters;
      expect(asked['kind'], 'movie');
      expect(asked['genre'], 'Action');
      expect(asked['vj'], 'vj-junior');
      expect(find.text('Movies · Action · VJ Junior'), findsWidgets);
      expect(find.byType(EditionTile), findsNWidgets(24));

      await tester.ensureVisible(find.text('Show more'));
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(api.requests.last.url.queryParameters['offset'], '24');
      expect(api.requests.last.url.queryParameters['genre'], 'Action');
      expect(find.byType(EditionTile), findsNWidgets(30));

      // Back: the choices are as they were.
      await tester.pageBack();
      await tester.pumpAndSettle();
      final chip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('choice-Action')),
      );
      expect(chip.selected, isTrue);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('choice-Action')))
            .selected,
        isFalse,
      );
    });

    testWidgets('an empty combination says so', (tester) async {
      final api = filterable();
      await pumpApp(tester, api, size: const Size(400, 1600));
      await goTo(tester, 'Filter');
      await tester.tap(find.text('Series').last);
      await tester.tap(find.byKey(const ValueKey('choice-Action')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      expect(find.byType(EditionTile), findsNothing);
      expect(find.text(l.nothingHereTitle), findsOneWidget);
    });

    testWidgets('a list that fails to load can be retried on its own', (
      tester,
    ) async {
      final api = filterable();
      var failGenres = true;
      api.intercept = (request) =>
          failGenres && request.url.path == '/api/v1/genres'
          ? Future.value(http.Response('{}', 503))
          : null;
      await pumpApp(tester, api, size: const Size(400, 1600));
      await goTo(tester, 'Filter');

      expect(find.text("Couldn't load Genre choices"), findsOneWidget);
      // The VJs loaded anyway.
      expect(find.byKey(const ValueKey('choice-vj-junior')), findsOneWidget);

      failGenres = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('choice-Action')), findsOneWidget);
    });
  });

  // --- Home -------------------------------------------------------------------

  group('Home shelves', () {
    testWidgets('genre shelves show only where titles exist, and See all '
        'opens the genre a page at a time', (tester) async {
      final api = titled(30)
        ..genres = [
          {'name': 'Action', 'editions': 30},
          {'name': 'Horror', 'editions': 0},
          {'name': 'Documentary', 'editions': 3},
        ];
      final semantics = tester.ensureSemantics();
      await pumpApp(tester, api, size: const Size(400, 4000));

      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Horror'), findsNothing);
      // Not one Home offers a shelf for.
      expect(find.text('Documentary'), findsNothing);
      // No title is fetched on its own for a shelf.
      expect(
        api.requests.where((r) => r.url.path == '/api/v1/genres'),
        hasLength(1),
      );
      expect(
        api.requests.where((r) => r.url.path.startsWith('/api/v1/editions/')),
        isEmpty,
      );

      await tester.tap(find.bySemanticsLabel('See all of Action'));
      await tester.pumpAndSettle();
      expect(find.byType(BrowseScreen), findsOneWidget);
      expect(api.requests.last.url.queryParameters['genre'], 'Action');
      expect(find.text('Show more'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('an empty or failed shelf is left out, the rest still show', (
      tester,
    ) async {
      final api = titled(3)
        ..genres = [
          {'name': 'Comedy', 'editions': 2},
        ]
        ..vjs.add({
          'id': 'v1',
          'name': 'VJ Junior',
          'slug': 'vj-junior',
          'editions': 1,
        });
      api.intercept = (request) =>
          request.url.queryParameters['genre'] == 'Comedy' ||
              request.url.queryParameters['kind'] == 'movie'
          ? Future.value(http.Response('{}', 500))
          : null;
      await pumpApp(tester, api, size: const Size(400, 3000));

      expect(find.text('Comedy'), findsNothing);
      expect(
        find.byKey(const ValueKey('row-vj:vj-junior')),
        findsOneWidget,
        reason: api.requests.map((r) => r.url).join('\n'),
      );
      expect(find.text('Latest'), findsOneWidget);
      expect(find.byKey(const ValueKey('row-movies')), findsNothing);
      expect(find.byKey(const ValueKey('row-series')), findsOneWidget);
    });

    testWidgets('the shortcuts go to Search and Filter', (tester) async {
      await pumpApp(tester, titled(2));
      await tester.tap(find.text('Search titles'));
      await tester.pumpAndSettle();
      expect(find.text('Find a movie, series or VJ'), findsOneWidget);
    });
  });

  // --- Navigation -------------------------------------------------------------

  testWidgets('an entry added to the menu keeps Search chosen and its text', (
    tester,
  ) async {
    final api = titled(2)..isAdmin = true;
    final adminAnswer = Completer<http.Response>();
    api.intercept = (request) =>
        request.url.path == '/api/v1/admin/me' ? adminAnswer.future : null;
    await pumpApp(tester, api, signedIn: true, size: const Size(400, 900));
    await goTo(tester, 'Search');
    await tester.enterText(find.byType(TextField), 'film');
    await tester.pump(const Duration(milliseconds: 400));

    // Admin appears in the menu now.
    adminAnswer.complete(json({'user_id': 'u1', 'admin': true}));
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('film'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 1);
  });

  // --- Startup ----------------------------------------------------------------

  group('startup', () {
    testWidgets('offline, the app opens with its downloads', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 900);
      addTearDown(tester.view.reset);
      // An expired session, and no network for sign-in or the catalogue.
      final offline = MockClient((_) async => throw http.ClientException('x'));
      final auth = AuthController(
        client: OAuthClient(
          config: OAuthConfig(
            issuer: _issuer,
            clientId: 'client-1',
            resource: 'https://api.example.test',
            redirectUri: Uri.parse(_callback),
            signOutPage: Uri.parse('https://pages.example.test/sign-out'),
          ),
          httpClient: offline,
          browserStep: (_, _) async => throw Exception('offline'),
        ),
        store: MemoryTokenStore(
          StoredSession(
            accessToken: 'A',
            refreshToken: 'R',
            expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
            email: 'offline@example.test',
          ),
        ),
      );
      final target = fakes.FakeTarget();
      target.statuses['7'] = const FileStatus(
        state: FileState.done,
        bytes: 10,
        total: 10,
      );
      final downloads = Downloads(
        target: target,
        api: null,
        records: MemoryDownloadRecords(
          jsonEncode({
            'downloads': [
              {
                'id': '7',
                'item_id': 'i7',
                'edition_id': 'e7',
                'title': 'Saved Film',
                'label': 'Luganda · VJ Junior',
                'quality': '720p',
                'file_name': 'Saved Film - 720p.mp4',
                'started_at': '2026-11-20T10:00:00Z',
              },
            ],
          }),
        ),
      );
      await tester.pumpWidget(
        VeloraApp(
          authController: auth,
          catalogueApi: CatalogueApi(
            baseUrl: Uri.parse(apiBase),
            httpClient: offline,
          ),
          downloads: downloads,
          appLock: AppLockController(
            authenticator: FakeLock(),
            store: MemoryLockSettingStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StartupScreen), findsNothing);
      expect(find.text(l.homeLoadFailed), findsOneWidget);
      // Still signed in: renewing waits for the network.
      expect(auth.status, AuthStatus.signedIn);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Downloads'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved Film'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('the startup screen has a label and never waits for ever', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final never = Completer<String?>();
      final auth = AuthController(
        client: OAuthClient(
          config: OAuthConfig(
            issuer: _issuer,
            clientId: 'c',
            resource: 'https://api.example.test',
            redirectUri: Uri.parse(_callback),
            signOutPage: Uri.parse('https://pages.example.test/sign-out'),
          ),
          httpClient: MockClient((_) async => http.Response('', 500)),
          browserStep: (_, _) async => throw Exception('x'),
        ),
        store: _SlowStore(never.future),
      );
      unawaited(auth.restore());
      await tester.pumpWidget(
        AuthScope(
          controller: auth,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const StartupGate(child: Text('the app')),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Starting VeloraUG'), findsOneWidget);
      await tester.pump(startupMaxWait);
      await tester.pump();
      expect(find.text('the app'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('with reduced motion the ring holds still', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: StartupScreen(),
          ),
        ),
      );
      // Nothing is animating, so the tree settles at once.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  // --- Account: switching and signing out -----------------------------------

  group('account pages', () {
    testWidgets('signing out hides the page, and another person gets a fresh '
        'one', (tester) async {
      final api = FakeApi()
        ..inbox = {
          'notifications': [
            {
              'id': 'payment.completed:1',
              'kind': 'payment_completed',
              'at': '2026-11-20T10:00:00Z',
              'read': false,
              'plan_name': 'Velora Prime',
              'device_label': null,
            },
          ],
          'unread': 1,
        };
      final fake = OAuthFake(first: 'aaa', later: ['bbb']);
      await fake.auth.restore();
      await pumpPage(
        tester,
        auth: fake.auth,
        api: api,
        page: notificationsPage,
      );
      expect(find.text('Payment confirmed'), findsOneWidget);

      // The other person has nothing.
      api.inbox = {'notifications': <Object>[], 'unread': 0};
      await fake.auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Payment confirmed'), findsNothing);
      expect(find.text(l.signInToSeeThis), findsOneWidget);

      await fake.auth.signIn();
      await tester.pumpAndSettle();
      expect(find.text('Payment confirmed'), findsNothing);
      expect(find.text(l.notificationsEmptyTitle), findsOneWidget);
    });

    testWidgets('a page needing sign-in, opened signed out, asks for it', (
      tester,
    ) async {
      final auth = fakeAuth(signedIn: false);
      await auth.restore();
      await pumpPage(
        tester,
        auth: auth,
        api: FakeApi(),
        page: notificationsPage,
      );
      expect(find.text(l.signInToSeeThis), findsOneWidget);
    });

    testWidgets('the Android-only Downloads page says so on the web', (
      tester,
    ) async {
      debugAndroidAppOverride = false;
      addTearDown(() => debugAndroidAppOverride = null);
      final auth = fakeAuth(signedIn: true);
      await auth.restore();
      await pumpPage(
        tester,
        auth: auth,
        api: FakeApi(),
        page: (context) => AccountPage(
          title: 'Downloads',
          androidOnly: true,
          access: AccountAccess.anyone,
          builder: (_) => const Text('the list'),
        ),
      );
      expect(find.text('the list'), findsNothing);
      expect(find.text(l.androidOnlyTitle), findsOneWidget);
    });
  });

  // --- Account integrations: failures ----------------------------------------

  group('notifications', () {
    Map<String, Object?> one({bool read = false}) => {
      'notifications': [
        {
          'id': 'device.removed:3c9e0d4f-1b2a-4c5d-8e6f-7a8b9c0d1e2f',
          'kind': 'device_removed',
          'at': '2026-11-20T10:00:00Z',
          'read': read,
          'plan_name': null,
          'device_label': 'Kitchen laptop',
        },
      ],
      'unread': read ? 0 : 1,
    };

    testWidgets('a failed load can be retried', (tester) async {
      final api = FakeApi()..inboxStatus = 503;
      final auth = fakeAuth(signedIn: true);
      await auth.restore();
      await pumpPage(tester, auth: auth, api: api, page: notificationsPage);
      expect(find.text(l.notificationsLoadFailed), findsOneWidget);

      api
        ..inboxStatus = 200
        ..inbox = one();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(l.noticeDeviceRemovedBody('Kitchen laptop')),
        findsOneWidget,
      );
      expect(find.text('1 unread'), findsOneWidget);
    });

    testWidgets('marked read only once the server says so', (tester) async {
      final api = FakeApi()
        ..inbox = one()
        ..markReadStatus = 503;
      final auth = fakeAuth(signedIn: true);
      await auth.restore();
      await pumpPage(tester, auth: auth, api: api, page: notificationsPage);

      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();
      expect(find.text(l.busy), findsOneWidget);
      expect(find.text('1 unread'), findsOneWidget);

      api.markReadStatus = 204;
      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();
      expect(find.text('1 unread'), findsNothing);
      expect(api.markedRead.last, {'all': true});
    });
  });

  testWidgets('history offers Resume only with a saved position', (
    tester,
  ) async {
    final api = FakeApi()
      ..history = [
        {
          'item_id': 'i1',
          'edition': card('e1', title: 'Fast X'),
          'season': null,
          'episode': null,
          'episode_title': null,
          'last_watched_at': '2026-11-21T10:00:00Z',
          'resume_seconds': 1500,
        },
        {
          'item_id': 'i2',
          'edition': card('e2', kind: 'series', title: 'Kabaka'),
          'season': 1,
          'episode': 2,
          'episode_title': 'The Crown',
          'last_watched_at': '2026-11-20T10:00:00Z',
          'resume_seconds': null,
        },
      ];
    final auth = fakeAuth(signedIn: true);
    await auth.restore();
    await pumpPage(
      tester,
      auth: auth,
      api: api,
      page: (context) =>
          AccountPage(title: 'History', builder: (_) => const HistoryBody()),
    );
    expect(find.text('Fast X'), findsOneWidget);
    expect(find.text(l.episodeHeading('Kabaka', 1, 2)), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
  });

  test(
    'push: what Android allows is shown, and the web says it has none',
    () async {
      final denied = await readPushStatus(
        isAndroid: true,
        readOsAllowed: () async => false,
      );
      expect(denied.availability, PushAvailability.notSetUp);
      expect(denied.osAllowed, isFalse);
      final unknown = await readPushStatus(
        isAndroid: true,
        readOsAllowed: () async => throw Exception('no channel'),
      );
      expect(unknown.osAllowed, isNull);
      final web = await readPushStatus(isAndroid: false);
      expect(web.availability, PushAvailability.notOnThisPlatform);
    },
  );

  // --- App lock ---------------------------------------------------------------

  group('App lock', () {
    test('turning it on or off needs the phone to pass; cancelling changes '
        'nothing', () async {
      final prompt = FakeLock()..answers.add(LockCheck.cancelled);
      final store = MemoryLockSettingStore();
      final lock = AppLockController(authenticator: prompt, store: store);
      await lock.load();
      expect(lock.enabled, isFalse);

      expect(await lock.setEnabled(true, 'on'), LockCheck.cancelled);
      expect(lock.enabled, isFalse);
      expect(store.enabled, isFalse);

      expect(await lock.setEnabled(true, 'on'), LockCheck.passed);
      expect(store.enabled, isTrue);
      prompt.answers.add(LockCheck.failed);
      expect(await lock.setEnabled(false, 'off'), LockCheck.failed);
      expect(store.enabled, isTrue);
      lock.dispose();
    });

    test('missing enrollment keeps the saved lock until system authentication succeeds', () async {
      final prompt = FakeLock(supported: false)
        ..answers.add(LockCheck.unavailable);
      final lock = AppLockController(
        authenticator: prompt,
        store: MemoryLockSettingStore(true),
      );
      await lock.load();
      expect(await lock.unlock('unlock'), LockCheck.unavailable);
      expect(lock.enabled, isTrue);
      expect(lock.locked, isTrue);
      prompt.supported = true;
      expect(await lock.unlock('unlock'), LockCheck.passed);
      expect(lock.locked, isFalse);
      lock.dispose();
    });

    test('it locks again after a minute away, not after a moment', () async {
      var now = DateTime(2026, 11, 24, 12);
      final lock = AppLockController(
        authenticator: FakeLock(),
        store: MemoryLockSettingStore(true),
        clock: () => now,
      );
      await lock.load();
      await lock.unlock('x');
      expect(lock.locked, isFalse);

      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 20));
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lock.locked, isFalse);

      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 2));
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lock.locked, isTrue);
      lock.dispose();
    });

    testWidgets('a cold start shows the lock, not the app, until it passes', (
      tester,
    ) async {
      final prompt = FakeLock()..answers.add(LockCheck.cancelled);
      final lock = AppLockController(
        authenticator: prompt,
        store: MemoryLockSettingStore(true),
      );
      addTearDown(lock.dispose);
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        VeloraApp(catalogueApi: titled(2).catalogue(), appLock: lock),
      );
      await tester.pumpAndSettle();

      expect(find.text(l.appLockLockedTitle), findsOneWidget);
      expect(find.text(l.appLockCancelled), findsOneWidget);
      // Nothing underneath can be read out.
      expect(find.bySemanticsLabel('Latest'), findsNothing);

      await tester.tap(find.text(l.appLockUnlock));
      await tester.pumpAndSettle();
      expect(find.text(l.appLockLockedTitle), findsNothing);
      expect(find.text('Latest'), findsOneWidget);
      semantics.dispose();
    });
  });

  // --- Danger zone ------------------------------------------------------------

  group('Danger zone', () {
    Future<OAuthFake> open(
      WidgetTester tester,
      FakeApi api, {
      List<String> later = const ['aaa'],
    }) async {
      final fake = OAuthFake(first: 'aaa', later: later);
      await fake.auth.restore();
      await pumpPage(
        tester,
        auth: fake.auth,
        api: api,
        page: (context) => AccountPage(
          title: 'Danger zone',
          builder: (_) => const DangerZoneBody(),
        ),
      );
      return fake;
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete my account'));
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    FakeApi available() => FakeApi()
      ..deletion = {'available': true, 'state': 'none', 'requested_at': null};

    testWidgets('while unavailable there is no way to delete', (tester) async {
      final api = FakeApi();
      await open(tester, api);
      expect(find.text(l.deletionUnavailableTitle), findsOneWidget);
      expect(find.text('Delete my account'), findsNothing);
      expect(api.deletions, 0);
    });

    testWidgets('it needs a fresh sign-in, as the same person', (tester) async {
      final api = available();
      final fake = await open(tester, api, later: ['zzz']);
      await confirm(tester);

      expect(fake.authorizeUrls.single.queryParameters['prompt'], 'login');
      expect(find.text(l.reauthDifferentAccount), findsOneWidget);
      // Nothing deleted, the other account's tokens dropped, still signed in
      // as before.
      expect(api.deletions, 0);
      expect(fake.revoked, ['R-zzz']);
      expect(fake.auth.accountKey, 'aaa');
    });

    testWidgets('a server asking for a newer sign-in is said plainly', (
      tester,
    ) async {
      final api = available()
        ..deletionAnswer = (
          401,
          {
            'detail': {'code': 'reauth_required', 'message': 'x'},
          },
        );
      await open(tester, api);
      await confirm(tester);
      expect(find.text(l.reauthNeeded), findsOneWidget);
    });

    testWidgets('one that stops part way can be finished, then signs out', (
      tester,
    ) async {
      final api = available()
        ..deletionAnswer = (
          502,
          {
            'detail': {'code': 'deletion_incomplete', 'message': 'x'},
          },
        );
      final fake = await open(tester, api, later: ['aaa', 'aaa']);
      await confirm(tester);
      expect(find.text(l.deletionIncompleteMessage), findsOneWidget);
      expect(find.text('Finish deleting my account'), findsOneWidget);
      expect(fake.auth.status, AuthStatus.signedIn);

      api.deletionAnswer = null;
      await tester.tap(find.text('Finish deleting my account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(api.deletions, 2);
      expect(fake.auth.status, AuthStatus.signedOut);
      expect(find.text(l.deletionDone), findsOneWidget);
    });
  });

  test('the account API turns answers into failures it can word', () async {
    final api = FakeApi()..historyStatus = 401;
    final auth = fakeAuth(signedIn: true);
    await auth.restore();
    final account = AccountApi(
      playback: api.playback(auth),
      catalogue: api.catalogue(),
    );
    await expectLater(
      account.history(),
      throwsA(
        isA<AccountException>().having(
          (e) => e.failure,
          'failure',
          AccountFailure.refused,
        ),
      ),
    );
    final signedOut = fakeAuth(signedIn: false);
    await signedOut.restore();
    await expectLater(
      AccountApi(
        playback: api.playback(signedOut),
        catalogue: api.catalogue(),
      ).notifications(),
      throwsA(
        isA<AccountException>().having(
          (e) => e.failure,
          'failure',
          AccountFailure.signedOut,
        ),
      ),
    );
  });
}

/// Never answers, like storage that hangs.
class _SlowStore implements TokenStore {
  _SlowStore(this.answer);

  final Future<String?> answer;

  @override
  Future<StoredSession?> read() async {
    await answer;
    return null;
  }

  @override
  Future<void> write(StoredSession session) async {}

  @override
  Future<void> clear() async {}
}
