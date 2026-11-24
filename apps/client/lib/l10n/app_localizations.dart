import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The product's name. Not translated.
  ///
  /// In en, this message translates to:
  /// **'VeloraUG'**
  String get appName;

  /// Navigation destination.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// Navigation destination.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Navigation destination and screen heading.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// Navigation destination, shown to admins only.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @loadingMore.
  ///
  /// In en, this message translates to:
  /// **'Loading more…'**
  String get loadingMore;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get saved;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied.'**
  String get copied;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required.'**
  String get required;

  /// No description provided for @showMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get showMore;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// Screen reader label for a row's See all.
  ///
  /// In en, this message translates to:
  /// **'See all of {row}'**
  String seeAllOf(String row);

  /// No description provided for @busy.
  ///
  /// In en, this message translates to:
  /// **'VeloraUG is busy right now. Try again in a moment.'**
  String get busy;

  /// No description provided for @unreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach VeloraUG. Check your connection and try again.'**
  String get unreachable;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get somethingWentWrong;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'This isn\'t available.'**
  String get notAvailable;

  /// No description provided for @noApiAddress.
  ///
  /// In en, this message translates to:
  /// **'This version of the app can\'t reach VeloraUG.'**
  String get noApiAddress;

  /// No description provided for @signInNotAccepted.
  ///
  /// In en, this message translates to:
  /// **'VeloraUG didn\'t accept your sign-in. Sign out, then sign in again.'**
  String get signInNotAccepted;

  /// No description provided for @numberBetween.
  ///
  /// In en, this message translates to:
  /// **'Use a whole number from {min} to {max}.'**
  String numberBetween(int min, int max);

  /// No description provided for @tooLong.
  ///
  /// In en, this message translates to:
  /// **'Use {max} characters or fewer.'**
  String tooLong(int max);

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @searchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search titles and VJs'**
  String get searchLabel;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @homeHeading.
  ///
  /// In en, this message translates to:
  /// **'Welcome to VeloraUG'**
  String get homeHeading;

  /// No description provided for @homeIntro.
  ///
  /// In en, this message translates to:
  /// **'Movies and series translated into Luganda by Uganda\'s VJs.'**
  String get homeIntro;

  /// No description provided for @catalogueNotSetUpTitle.
  ///
  /// In en, this message translates to:
  /// **'The catalogue isn\'t set up'**
  String get catalogueNotSetUpTitle;

  /// No description provided for @catalogueNotSetUpMessage.
  ///
  /// In en, this message translates to:
  /// **'This version of the app has no address for VeloraUG\'s service, so it has nothing to show.'**
  String get catalogueNotSetUpMessage;

  /// No description provided for @homeLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the catalogue'**
  String get homeLoadFailed;

  /// No description provided for @listLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this list'**
  String get listLoadFailed;

  /// No description provided for @nothingYetTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to watch yet'**
  String get nothingYetTitle;

  /// No description provided for @nothingHereTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get nothingHereTitle;

  /// No description provided for @nothingYetMessage.
  ///
  /// In en, this message translates to:
  /// **'New movies and series will appear here as soon as they are added.'**
  String get nothingYetMessage;

  /// No description provided for @latest.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get latest;

  /// No description provided for @movies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get movies;

  /// No description provided for @series.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get series;

  /// No description provided for @movie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get movie;

  /// A single series, as on a card or in a list of facts.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get seriesBadge;

  /// A row of editions in one language.
  ///
  /// In en, this message translates to:
  /// **'In {language}'**
  String inLanguage(String language);

  /// No description provided for @loadingTitles.
  ///
  /// In en, this message translates to:
  /// **'Loading titles'**
  String get loadingTitles;

  /// No description provided for @loadingVj.
  ///
  /// In en, this message translates to:
  /// **'Loading the VJ'**
  String get loadingVj;

  /// No description provided for @vjNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'This VJ isn\'t available'**
  String get vjNotFoundTitle;

  /// No description provided for @vjNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'They may have nothing published yet. Go back to find something else to watch.'**
  String get vjNotFoundMessage;

  /// No description provided for @vjLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this VJ'**
  String get vjLoadFailed;

  /// No description provided for @vjNoBio.
  ///
  /// In en, this message translates to:
  /// **'No biography yet.'**
  String get vjNoBio;

  /// No description provided for @loadingEdition.
  ///
  /// In en, this message translates to:
  /// **'Loading the title'**
  String get loadingEdition;

  /// No description provided for @editionNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'This title isn\'t available'**
  String get editionNotFoundTitle;

  /// No description provided for @editionNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'It may have been removed from VeloraUG. Go back to find something else to watch.'**
  String get editionNotFoundMessage;

  /// No description provided for @editionLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this title'**
  String get editionLoadFailed;

  /// No description provided for @editionLabelLink.
  ///
  /// In en, this message translates to:
  /// **'{label}. Opens the VJ\'s page.'**
  String editionLabelLink(String label);

  /// No description provided for @alsoKnownAs.
  ///
  /// In en, this message translates to:
  /// **'Original title: {title}'**
  String alsoKnownAs(String title);

  /// No description provided for @runtimeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String runtimeMinutes(int minutes);

  /// No description provided for @runtimeHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String runtimeHours(int hours);

  /// No description provided for @runtimeHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String runtimeHoursMinutes(int hours, int minutes);

  /// No description provided for @trailer.
  ///
  /// In en, this message translates to:
  /// **'Trailer'**
  String get trailer;

  /// No description provided for @watch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get watch;

  /// No description provided for @signInToWatchButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in to watch'**
  String get signInToWatchButton;

  /// No description provided for @signInFirst.
  ///
  /// In en, this message translates to:
  /// **'Sign in first'**
  String get signInFirst;

  /// No description provided for @notAvailableHere.
  ///
  /// In en, this message translates to:
  /// **'Not available here'**
  String get notAvailableHere;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @episodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get episodes;

  /// No description provided for @noEpisodesTitle.
  ///
  /// In en, this message translates to:
  /// **'No episodes yet'**
  String get noEpisodesTitle;

  /// No description provided for @noEpisodesMessage.
  ///
  /// In en, this message translates to:
  /// **'Episodes will appear here as soon as they are added.'**
  String get noEpisodesMessage;

  /// No description provided for @seasonNumber.
  ///
  /// In en, this message translates to:
  /// **'Season {season}'**
  String seasonNumber(int season);

  /// No description provided for @episodeNumber.
  ///
  /// In en, this message translates to:
  /// **'Episode {episode}'**
  String episodeNumber(int episode);

  /// No description provided for @playEpisode.
  ///
  /// In en, this message translates to:
  /// **'Play season {season}, episode {episode}'**
  String playEpisode(int season, int episode);

  /// No description provided for @gettingReady.
  ///
  /// In en, this message translates to:
  /// **'Getting the video ready'**
  String get gettingReady;

  /// No description provided for @couldNotPlay.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play this'**
  String get couldNotPlay;

  /// No description provided for @playbackStopped.
  ///
  /// In en, this message translates to:
  /// **'Playback stopped. Check your connection, then try again from where you were.'**
  String get playbackStopped;

  /// No description provided for @episodeHeading.
  ///
  /// In en, this message translates to:
  /// **'{title} · S{season} E{episode}'**
  String episodeHeading(String title, int season, int episode);

  /// No description provided for @nextEpisode.
  ///
  /// In en, this message translates to:
  /// **'Next episode'**
  String get nextEpisode;

  /// No description provided for @nextEpisodeOf.
  ///
  /// In en, this message translates to:
  /// **'Next episode: season {season}, episode {episode}'**
  String nextEpisodeOf(int season, int episode);

  /// No description provided for @upNext.
  ///
  /// In en, this message translates to:
  /// **'Up next: S{season} E{episode}'**
  String upNext(int season, int episode);

  /// No description provided for @loadingVideo.
  ///
  /// In en, this message translates to:
  /// **'Loading the video'**
  String get loadingVideo;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @position.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get position;

  /// No description provided for @signInToWatch.
  ///
  /// In en, this message translates to:
  /// **'Sign in to watch.'**
  String get signInToWatch;

  /// No description provided for @notReadyToWatch.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be watched yet.'**
  String get notReadyToWatch;

  /// No description provided for @adminOnly.
  ///
  /// In en, this message translates to:
  /// **'This account isn\'t an admin.'**
  String get adminOnly;

  /// No description provided for @searchHeading.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchHeading;

  /// No description provided for @searchIdleTitle.
  ///
  /// In en, this message translates to:
  /// **'Find a movie, series or VJ'**
  String get searchIdleTitle;

  /// No description provided for @searchIdleMessage.
  ///
  /// In en, this message translates to:
  /// **'Type at least {count} letters of a title or a VJ\'s name.'**
  String searchIdleMessage(int count);

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t search'**
  String get searchFailed;

  /// No description provided for @searchNoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches'**
  String get searchNoneTitle;

  /// No description provided for @searchNoneMessage.
  ///
  /// In en, this message translates to:
  /// **'No title or VJ in VeloraUG matches \"{query}\".'**
  String searchNoneMessage(String query);

  /// No description provided for @searchResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result for \"{query}\"} other{{count} results for \"{query}\"}}'**
  String searchResultCount(int count, String query);

  /// No description provided for @searchResultsFor.
  ///
  /// In en, this message translates to:
  /// **'Results for \"{query}\"'**
  String searchResultsFor(String query);

  /// No description provided for @signedOutTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re signed out'**
  String get signedOutTitle;

  /// No description provided for @signedInTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re signed in'**
  String get signedInTitle;

  /// No description provided for @signInNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'Sign-in isn\'t set up in this version of the app.'**
  String get signInNotSetUp;

  /// No description provided for @checkingSignIn.
  ///
  /// In en, this message translates to:
  /// **'Checking your sign-in'**
  String get checkingSignIn;

  /// No description provided for @takesAMoment.
  ///
  /// In en, this message translates to:
  /// **'This takes a moment.'**
  String get takesAMoment;

  /// No description provided for @signInExplained.
  ///
  /// In en, this message translates to:
  /// **'Sign in, or create an account, on the VeloraUG sign-in page. It opens in your browser.'**
  String get signInExplained;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @waitingForSignIn.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the sign-in page…'**
  String get waitingForSignIn;

  /// No description provided for @signingOut.
  ///
  /// In en, this message translates to:
  /// **'Signing out…'**
  String get signingOut;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}.'**
  String signedInAs(String email);

  /// No description provided for @signedInOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Your account is signed in on this device.'**
  String get signedInOnDevice;

  /// No description provided for @signInCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was cancelled, so you\'re still signed out.'**
  String get signInCancelled;

  /// No description provided for @signInBrowserFailed.
  ///
  /// In en, this message translates to:
  /// **'The sign-in page couldn\'t open. Check that a browser is available, and on the web that pop-ups are allowed, then try again.'**
  String get signInBrowserFailed;

  /// No description provided for @signInDenied.
  ///
  /// In en, this message translates to:
  /// **'You didn\'t allow VeloraUG to use your account, so you\'re still signed out.'**
  String get signInDenied;

  /// No description provided for @signInTimedOut.
  ///
  /// In en, this message translates to:
  /// **'The sign-in timed out. Press Sign in to start again.'**
  String get signInTimedOut;

  /// No description provided for @signInNetwork.
  ///
  /// In en, this message translates to:
  /// **'VeloraUG couldn\'t reach the sign-in service. Check your connection and try again.'**
  String get signInNetwork;

  /// No description provided for @signInUnverified.
  ///
  /// In en, this message translates to:
  /// **'The sign-in couldn\'t be verified, so it was stopped. Please try again.'**
  String get signInUnverified;

  /// No description provided for @signInTryAgain.
  ///
  /// In en, this message translates to:
  /// **'The sign-in didn\'t finish. Please try again.'**
  String get signInTryAgain;

  /// No description provided for @sessionEnded.
  ///
  /// In en, this message translates to:
  /// **'Your sign-in has ended. Sign in again to continue.'**
  String get sessionEnded;

  /// No description provided for @signedOutNotice.
  ///
  /// In en, this message translates to:
  /// **'You\'re signed out.'**
  String get signedOutNotice;

  /// No description provided for @signedOutOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re signed out on this device. VeloraUG couldn\'t reach the sign-in service, so the browser may still remember you. On a shared device, sign in and out again when you are online.'**
  String get signedOutOffline;

  /// No description provided for @signedOutBrowserKept.
  ///
  /// In en, this message translates to:
  /// **'You\'re signed out on this device, but the browser sign-out didn\'t finish, so the browser may still remember you. On a shared device, sign in and out again.'**
  String get signedOutBrowserKept;

  /// No description provided for @credits.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get credits;

  /// No description provided for @aboutTmdb.
  ///
  /// In en, this message translates to:
  /// **'Movie and series titles, descriptions and images come from TMDB, The Movie Database.'**
  String get aboutTmdb;

  /// No description provided for @tmdbLogo.
  ///
  /// In en, this message translates to:
  /// **'TMDB logo'**
  String get tmdbLogo;

  /// TMDB's required wording, word for word. Keep it in English unless TMDB gives a translation.
  ///
  /// In en, this message translates to:
  /// **'This product uses the TMDB API but is not endorsed or certified by TMDB.'**
  String get tmdbNotice;

  /// No description provided for @yourProfile.
  ///
  /// In en, this message translates to:
  /// **'Your profile'**
  String get yourProfile;

  /// No description provided for @loadingProfile.
  ///
  /// In en, this message translates to:
  /// **'Loading your profile…'**
  String get loadingProfile;

  /// No description provided for @noDisplayName.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t set a display name yet.'**
  String get noDisplayName;

  /// No description provided for @displayNameIs.
  ///
  /// In en, this message translates to:
  /// **'Your display name is {name}.'**
  String displayNameIs(String name);

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @displayNameHelp.
  ///
  /// In en, this message translates to:
  /// **'Up to {max} characters. Leave it empty to remove it.'**
  String displayNameHelp(int max);

  /// No description provided for @nameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Use {max} characters or fewer.'**
  String nameTooLong(int max);

  /// No description provided for @nameRemoved.
  ///
  /// In en, this message translates to:
  /// **'Your name was removed.'**
  String get nameRemoved;

  /// No description provided for @saveName.
  ///
  /// In en, this message translates to:
  /// **'Save name'**
  String get saveName;

  /// No description provided for @profileSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see your profile.'**
  String get profileSignedOut;

  /// No description provided for @profileInvalidName.
  ///
  /// In en, this message translates to:
  /// **'Use 1 to 80 characters for your name.'**
  String get profileInvalidName;

  /// No description provided for @adminNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'The admin screens aren\'t set up in this version of the app.'**
  String get adminNotSetUp;

  /// No description provided for @adminSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Sign in as an admin to do this.'**
  String get adminSignedOut;

  /// No description provided for @adminNotFound.
  ///
  /// In en, this message translates to:
  /// **'That no longer exists. Refresh to see the latest.'**
  String get adminNotFound;

  /// No description provided for @adminConflict.
  ///
  /// In en, this message translates to:
  /// **'That can\'t be done right now.'**
  String get adminConflict;

  /// No description provided for @adminInvalid.
  ///
  /// In en, this message translates to:
  /// **'VeloraUG refused that.'**
  String get adminInvalid;

  /// No description provided for @adminBadImage.
  ///
  /// In en, this message translates to:
  /// **'Use a JPEG, PNG or WebP image of at most 2 MB.'**
  String get adminBadImage;

  /// No description provided for @adminLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this'**
  String get adminLoadFailed;

  /// No description provided for @adminDrafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get adminDrafts;

  /// No description provided for @adminVjs.
  ///
  /// In en, this message translates to:
  /// **'VJs'**
  String get adminVjs;

  /// No description provided for @adminSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get adminSettings;

  /// No description provided for @statusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get statusDraft;

  /// No description provided for @statusPublished.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get statusPublished;

  /// No description provided for @statusHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get statusHidden;

  /// No description provided for @testFilm.
  ///
  /// In en, this message translates to:
  /// **'Test film'**
  String get testFilm;

  /// No description provided for @noVjYet.
  ///
  /// In en, this message translates to:
  /// **'No VJ yet'**
  String get noVjYet;

  /// No description provided for @needed.
  ///
  /// In en, this message translates to:
  /// **'Needed'**
  String get needed;

  /// No description provided for @adminDraftsIntro.
  ///
  /// In en, this message translates to:
  /// **'Drafts, hidden titles, and series with new episodes waiting. Each says what it still needs.'**
  String get adminDraftsIntro;

  /// No description provided for @newDraft.
  ///
  /// In en, this message translates to:
  /// **'New draft'**
  String get newDraft;

  /// No description provided for @noDraftsTitle.
  ///
  /// In en, this message translates to:
  /// **'No drafts'**
  String get noDraftsTitle;

  /// No description provided for @noDraftsMessage.
  ///
  /// In en, this message translates to:
  /// **'Start a draft for each translated movie or series, then upload its video with the key it gives you.'**
  String get noDraftsMessage;

  /// No description provided for @stillNeeds.
  ///
  /// In en, this message translates to:
  /// **'Still needs: {list}'**
  String stillNeeds(String list);

  /// No description provided for @episodesWaiting.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 episode waiting for approval} other{{count} episodes waiting for approval}}'**
  String episodesWaiting(int count);

  /// No description provided for @readyToPublish.
  ///
  /// In en, this message translates to:
  /// **'Ready to publish.'**
  String get readyToPublish;

  /// No description provided for @newDraftIntro.
  ///
  /// In en, this message translates to:
  /// **'Give the title as the VJ\'s edition is known. Details, poster and VJ credit come after the video is uploaded.'**
  String get newDraftIntro;

  /// No description provided for @titleAsSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleAsSubmitted;

  /// No description provided for @titleAsSubmittedHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown to viewers. TMDB is searched with it.'**
  String get titleAsSubmittedHelp;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @yearOptional.
  ///
  /// In en, this message translates to:
  /// **'Year (optional)'**
  String get yearOptional;

  /// No description provided for @season.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get season;

  /// No description provided for @episode.
  ///
  /// In en, this message translates to:
  /// **'Episode'**
  String get episode;

  /// No description provided for @episodeTitleOptional.
  ///
  /// In en, this message translates to:
  /// **'Episode title (optional)'**
  String get episodeTitleOptional;

  /// No description provided for @startDraft.
  ///
  /// In en, this message translates to:
  /// **'Start draft'**
  String get startDraft;

  /// No description provided for @uploadKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload key'**
  String get uploadKeyTitle;

  /// No description provided for @uploadKeyOnce.
  ///
  /// In en, this message translates to:
  /// **'Copy this key now. It is shown only once, and VeloraUG doesn\'t keep it.'**
  String get uploadKeyOnce;

  /// No description provided for @uploadKeyExpires.
  ///
  /// In en, this message translates to:
  /// **'It works until {date}, for one upload.'**
  String uploadKeyExpires(String date);

  /// No description provided for @uploadKeyHowTo.
  ///
  /// In en, this message translates to:
  /// **'Upload the video with: python tools/veloraug_upload.py <file>, and paste the key when asked.'**
  String get uploadKeyHowTo;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get draft;

  /// No description provided for @renameTitle.
  ///
  /// In en, this message translates to:
  /// **'Change the title'**
  String get renameTitle;

  /// No description provided for @displayTitle.
  ///
  /// In en, this message translates to:
  /// **'Title shown to viewers'**
  String get displayTitle;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @videosIntro.
  ///
  /// In en, this message translates to:
  /// **'Preview each video before confirming its VJ credit.'**
  String get videosIntro;

  /// No description provided for @addEpisode.
  ///
  /// In en, this message translates to:
  /// **'Add episode'**
  String get addEpisode;

  /// No description provided for @movieVideo.
  ///
  /// In en, this message translates to:
  /// **'The movie'**
  String get movieVideo;

  /// No description provided for @episodeShort.
  ///
  /// In en, this message translates to:
  /// **'S{season} E{episode}'**
  String episodeShort(int season, int episode);

  /// No description provided for @approved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approved;

  /// No description provided for @waitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get waitingApproval;

  /// No description provided for @fileName.
  ///
  /// In en, this message translates to:
  /// **'File: {name}'**
  String fileName(String name);

  /// No description provided for @fileTags.
  ///
  /// In en, this message translates to:
  /// **'Tags: {tags}'**
  String fileTags(String tags);

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @approveEpisode.
  ///
  /// In en, this message translates to:
  /// **'Approve episode'**
  String get approveEpisode;

  /// No description provided for @episodeApproved.
  ///
  /// In en, this message translates to:
  /// **'Episode approved. Viewers can now watch it.'**
  String get episodeApproved;

  /// No description provided for @newUploadKey.
  ///
  /// In en, this message translates to:
  /// **'New upload key'**
  String get newUploadKey;

  /// No description provided for @keyLabel.
  ///
  /// In en, this message translates to:
  /// **'Who it\'s for'**
  String get keyLabel;

  /// No description provided for @keyLabelHelp.
  ///
  /// In en, this message translates to:
  /// **'A name to tell keys apart, such as \"Owner\" or \"Better copy\".'**
  String get keyLabelHelp;

  /// No description provided for @keyLabelDefault.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get keyLabelDefault;

  /// No description provided for @keyLine.
  ///
  /// In en, this message translates to:
  /// **'Key \"{label}\", unused, until {date}'**
  String keyLine(String label, String date);

  /// No description provided for @revoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revoke;

  /// No description provided for @revokeKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke this key?'**
  String get revokeKeyTitle;

  /// No description provided for @revokeKeyMessage.
  ///
  /// In en, this message translates to:
  /// **'The key \"{label}\" will stop working at once.'**
  String revokeKeyMessage(String label);

  /// No description provided for @keyRevoked.
  ///
  /// In en, this message translates to:
  /// **'Key revoked.'**
  String get keyRevoked;

  /// No description provided for @videoNone.
  ///
  /// In en, this message translates to:
  /// **'Not uploaded'**
  String get videoNone;

  /// No description provided for @videoUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get videoUploading;

  /// No description provided for @videoChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get videoChecking;

  /// No description provided for @videoConverting.
  ///
  /// In en, this message translates to:
  /// **'Converting'**
  String get videoConverting;

  /// No description provided for @videoReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get videoReady;

  /// No description provided for @videoRefused.
  ///
  /// In en, this message translates to:
  /// **'Refused'**
  String get videoRefused;

  /// No description provided for @videoFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get videoFailed;

  /// No description provided for @videoRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get videoRemoved;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @lookupWaiting.
  ///
  /// In en, this message translates to:
  /// **'TMDB is searched once the video is ready.'**
  String get lookupWaiting;

  /// No description provided for @lookupClear.
  ///
  /// In en, this message translates to:
  /// **'TMDB found a clear match, filled in below.'**
  String get lookupClear;

  /// No description provided for @lookupChoose.
  ///
  /// In en, this message translates to:
  /// **'TMDB found several possible titles. Choose the right one.'**
  String get lookupChoose;

  /// No description provided for @lookupNone.
  ///
  /// In en, this message translates to:
  /// **'TMDB found nothing. Search again with another title, give a TMDB ID, or type the details in.'**
  String get lookupNone;

  /// No description provided for @lookupFailed.
  ///
  /// In en, this message translates to:
  /// **'TMDB couldn\'t be reached. Search again, or type the details in.'**
  String get lookupFailed;

  /// No description provided for @lookupChosen.
  ///
  /// In en, this message translates to:
  /// **'Details chosen from TMDB.'**
  String get lookupChosen;

  /// No description provided for @lookupManual.
  ///
  /// In en, this message translates to:
  /// **'Details typed in.'**
  String get lookupManual;

  /// No description provided for @tmdbId.
  ///
  /// In en, this message translates to:
  /// **'TMDB {id}'**
  String tmdbId(int id);

  /// No description provided for @useThis.
  ///
  /// In en, this message translates to:
  /// **'Use this'**
  String get useThis;

  /// No description provided for @searchTmdbAgain.
  ///
  /// In en, this message translates to:
  /// **'Search TMDB again'**
  String get searchTmdbAgain;

  /// No description provided for @titleToSearch.
  ///
  /// In en, this message translates to:
  /// **'Title to search'**
  String get titleToSearch;

  /// No description provided for @titleToSearchHelp.
  ///
  /// In en, this message translates to:
  /// **'Without the VJ\'s name or words like \"translated\".'**
  String get titleToSearchHelp;

  /// No description provided for @useTmdbId.
  ///
  /// In en, this message translates to:
  /// **'Use a TMDB ID'**
  String get useTmdbId;

  /// No description provided for @tmdbIdLabel.
  ///
  /// In en, this message translates to:
  /// **'TMDB ID'**
  String get tmdbIdLabel;

  /// No description provided for @tmdbIdHelpMovie.
  ///
  /// In en, this message translates to:
  /// **'The number in the movie\'s address on themoviedb.org.'**
  String get tmdbIdHelpMovie;

  /// No description provided for @tmdbIdHelpSeries.
  ///
  /// In en, this message translates to:
  /// **'The number in the series\' address on themoviedb.org.'**
  String get tmdbIdHelpSeries;

  /// No description provided for @typeDetails.
  ///
  /// In en, this message translates to:
  /// **'Type the details in'**
  String get typeDetails;

  /// No description provided for @originalTitle.
  ///
  /// In en, this message translates to:
  /// **'Original title'**
  String get originalTitle;

  /// No description provided for @runtimeOptional.
  ///
  /// In en, this message translates to:
  /// **'Length in minutes (optional)'**
  String get runtimeOptional;

  /// No description provided for @genresOptional.
  ///
  /// In en, this message translates to:
  /// **'Genres (optional)'**
  String get genresOptional;

  /// No description provided for @genresHelp.
  ///
  /// In en, this message translates to:
  /// **'Separated by commas, such as: Action, Drama'**
  String get genresHelp;

  /// No description provided for @overviewOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get overviewOptional;

  /// No description provided for @poster.
  ///
  /// In en, this message translates to:
  /// **'Poster'**
  String get poster;

  /// No description provided for @showTmdbPosters.
  ///
  /// In en, this message translates to:
  /// **'Show TMDB\'s posters'**
  String get showTmdbPosters;

  /// No description provided for @uploadPoster.
  ///
  /// In en, this message translates to:
  /// **'Upload a poster'**
  String get uploadPoster;

  /// No description provided for @noTmdbPosters.
  ///
  /// In en, this message translates to:
  /// **'TMDB has no English posters for this title. Upload one instead.'**
  String get noTmdbPosters;

  /// No description provided for @choosePoster.
  ///
  /// In en, this message translates to:
  /// **'Use this poster'**
  String get choosePoster;

  /// No description provided for @posterUploaded.
  ///
  /// In en, this message translates to:
  /// **'Poster uploaded and chosen.'**
  String get posterUploaded;

  /// No description provided for @imageTooBig.
  ///
  /// In en, this message translates to:
  /// **'That image is over 2 MB. Use a smaller one.'**
  String get imageTooBig;

  /// No description provided for @vjCredit.
  ///
  /// In en, this message translates to:
  /// **'VJ credit'**
  String get vjCredit;

  /// No description provided for @creditIntro.
  ///
  /// In en, this message translates to:
  /// **'Nothing is credited until you confirm it. Preview the video first: a wrong credit is a real harm to a VJ.'**
  String get creditIntro;

  /// No description provided for @creditedTo.
  ///
  /// In en, this message translates to:
  /// **'Credited to {name}.'**
  String creditedTo(String name);

  /// No description provided for @suggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggested from the file'**
  String get suggestions;

  /// No description provided for @noSuggestions.
  ///
  /// In en, this message translates to:
  /// **'The file names no known VJ. Choose one, or add a new VJ.'**
  String get noSuggestions;

  /// No description provided for @suggestionLine.
  ///
  /// In en, this message translates to:
  /// **'{name}, found in {foundIn}'**
  String suggestionLine(String name, String foundIn);

  /// No description provided for @creditThisVj.
  ///
  /// In en, this message translates to:
  /// **'Credit this VJ'**
  String get creditThisVj;

  /// No description provided for @addAndCredit.
  ///
  /// In en, this message translates to:
  /// **'Add {name} and credit them'**
  String addAndCredit(String name);

  /// No description provided for @chooseVj.
  ///
  /// In en, this message translates to:
  /// **'Choose a VJ'**
  String get chooseVj;

  /// No description provided for @addNewVj.
  ///
  /// In en, this message translates to:
  /// **'Add a new VJ'**
  String get addNewVj;

  /// No description provided for @vjName.
  ///
  /// In en, this message translates to:
  /// **'VJ\'s name'**
  String get vjName;

  /// No description provided for @confirmCreditTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm the VJ credit'**
  String get confirmCreditTitle;

  /// No description provided for @confirmCreditMessage.
  ///
  /// In en, this message translates to:
  /// **'Credit {name} for \"{title}\"? Confirm only after previewing the video.'**
  String confirmCreditMessage(String name, String title);

  /// No description provided for @confirmCredit.
  ///
  /// In en, this message translates to:
  /// **'Confirm credit'**
  String get confirmCredit;

  /// No description provided for @missingVideo.
  ///
  /// In en, this message translates to:
  /// **'a ready video'**
  String get missingVideo;

  /// No description provided for @missingDetails.
  ///
  /// In en, this message translates to:
  /// **'details, from TMDB or typed in'**
  String get missingDetails;

  /// No description provided for @missingPoster.
  ///
  /// In en, this message translates to:
  /// **'a chosen poster'**
  String get missingPoster;

  /// No description provided for @missingCredit.
  ///
  /// In en, this message translates to:
  /// **'a confirmed VJ credit'**
  String get missingCredit;

  /// No description provided for @publishing.
  ///
  /// In en, this message translates to:
  /// **'Publishing'**
  String get publishing;

  /// No description provided for @cantPublishYet.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be published yet. It still needs:'**
  String get cantPublishYet;

  /// No description provided for @publishedExplained.
  ///
  /// In en, this message translates to:
  /// **'Viewers can see this. New episodes wait for your approval.'**
  String get publishedExplained;

  /// No description provided for @publish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publish;

  /// No description provided for @publishedNow.
  ///
  /// In en, this message translates to:
  /// **'Published. Viewers can now see it.'**
  String get publishedNow;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @hideTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide this title?'**
  String get hideTitle;

  /// No description provided for @hideMessage.
  ///
  /// In en, this message translates to:
  /// **'Viewers won\'t see it, and anyone watching it is stopped. You can publish it again later.'**
  String get hideMessage;

  /// No description provided for @hiddenNow.
  ///
  /// In en, this message translates to:
  /// **'Hidden from viewers.'**
  String get hiddenNow;

  /// No description provided for @adminVjsIntro.
  ///
  /// In en, this message translates to:
  /// **'Every VJ, published or not. Other spellings help suggest the credit from a file\'s name.'**
  String get adminVjsIntro;

  /// No description provided for @addVj.
  ///
  /// In en, this message translates to:
  /// **'Add a VJ'**
  String get addVj;

  /// No description provided for @editVj.
  ///
  /// In en, this message translates to:
  /// **'Change this VJ'**
  String get editVj;

  /// No description provided for @noVjsTitle.
  ///
  /// In en, this message translates to:
  /// **'No VJs yet'**
  String get noVjsTitle;

  /// No description provided for @noVjsMessage.
  ///
  /// In en, this message translates to:
  /// **'Add a VJ here, or while confirming a credit.'**
  String get noVjsMessage;

  /// No description provided for @publishedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing published} =1{1 published} other{{count} published}}'**
  String publishedCount(int count);

  /// No description provided for @alsoSpelled.
  ///
  /// In en, this message translates to:
  /// **'Also: {names}'**
  String alsoSpelled(String names);

  /// No description provided for @uploadPhoto.
  ///
  /// In en, this message translates to:
  /// **'Upload a photo'**
  String get uploadPhoto;

  /// No description provided for @photoUploaded.
  ///
  /// In en, this message translates to:
  /// **'Photo uploaded.'**
  String get photoUploaded;

  /// No description provided for @photoAfterAdding.
  ///
  /// In en, this message translates to:
  /// **'Add the VJ first, then their photo.'**
  String get photoAfterAdding;

  /// No description provided for @vjNameHelp.
  ///
  /// In en, this message translates to:
  /// **'As viewers know them, such as \"VJ Junior\". Shown on posters.'**
  String get vjNameHelp;

  /// No description provided for @otherSpellings.
  ///
  /// In en, this message translates to:
  /// **'Other spellings (optional)'**
  String get otherSpellings;

  /// No description provided for @otherSpellingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Separated by commas, as they appear in file names.'**
  String get otherSpellingsHelp;

  /// No description provided for @bio.
  ///
  /// In en, this message translates to:
  /// **'Biography (optional)'**
  String get bio;

  /// No description provided for @admins.
  ///
  /// In en, this message translates to:
  /// **'Admins'**
  String get admins;

  /// No description provided for @adminsIntro.
  ///
  /// In en, this message translates to:
  /// **'Admins can publish titles and add or remove other admins. The last admin can\'t be removed.'**
  String get adminsIntro;

  /// No description provided for @addedOn.
  ///
  /// In en, this message translates to:
  /// **'Added on {date}'**
  String addedOn(String date);

  /// No description provided for @addedByOn.
  ///
  /// In en, this message translates to:
  /// **'Added by {email} on {date}'**
  String addedByOn(String email, String date);

  /// No description provided for @lastAdmin.
  ///
  /// In en, this message translates to:
  /// **'Last admin'**
  String get lastAdmin;

  /// No description provided for @adminEmail.
  ///
  /// In en, this message translates to:
  /// **'Email of the new admin'**
  String get adminEmail;

  /// No description provided for @adminEmailHelp.
  ///
  /// In en, this message translates to:
  /// **'They must have signed in to VeloraUG once, and confirmed this email.'**
  String get adminEmailHelp;

  /// No description provided for @enterEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter an email address.'**
  String get enterEmail;

  /// No description provided for @addAdmin.
  ///
  /// In en, this message translates to:
  /// **'Add admin'**
  String get addAdmin;

  /// No description provided for @adminAdded.
  ///
  /// In en, this message translates to:
  /// **'{email} is now an admin.'**
  String adminAdded(String email);

  /// No description provided for @adminRemoved.
  ///
  /// In en, this message translates to:
  /// **'{who} is no longer an admin.'**
  String adminRemoved(String who);

  /// No description provided for @removeAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this admin?'**
  String get removeAdminTitle;

  /// No description provided for @removeAdminMessage.
  ///
  /// In en, this message translates to:
  /// **'{who} will no longer see the admin screens.'**
  String removeAdminMessage(String who);

  /// No description provided for @languages.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get languages;

  /// No description provided for @languagesIntro.
  ///
  /// In en, this message translates to:
  /// **'Editions can be in any of these. Browsing by language appears once a second language has something published.'**
  String get languagesIntro;

  /// No description provided for @languageCode.
  ///
  /// In en, this message translates to:
  /// **'Language code'**
  String get languageCode;

  /// No description provided for @languageCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'Two or three letters, such as \"nyn\" for Runyankole.'**
  String get languageCodeHelp;

  /// No description provided for @languageCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use two or three letters.'**
  String get languageCodeInvalid;

  /// No description provided for @languageName.
  ///
  /// In en, this message translates to:
  /// **'Language name'**
  String get languageName;

  /// No description provided for @addLanguage.
  ///
  /// In en, this message translates to:
  /// **'Add language'**
  String get addLanguage;

  /// No description provided for @languageAdded.
  ///
  /// In en, this message translates to:
  /// **'{name} added.'**
  String languageAdded(String name);

  /// No description provided for @adminUploads.
  ///
  /// In en, this message translates to:
  /// **'Uploads'**
  String get adminUploads;

  /// No description provided for @adminUploadsIntro.
  ///
  /// In en, this message translates to:
  /// **'Upload videos from this browser. Each file becomes a draft, or an episode of a series, and carries on after a lost connection, a closed tab or a power cut.'**
  String get adminUploadsIntro;

  /// No description provided for @uploadsNotSetUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Uploading isn\'t set up'**
  String get uploadsNotSetUpTitle;

  /// No description provided for @uploadsNotSetUpMessage.
  ///
  /// In en, this message translates to:
  /// **'This build has no upload address. Upload with tools/veloraug_upload.py instead, or set UPLOAD_BASE_URL.'**
  String get uploadsNotSetUpMessage;

  /// No description provided for @dropVideosHere.
  ///
  /// In en, this message translates to:
  /// **'Drag video files here'**
  String get dropVideosHere;

  /// No description provided for @dropToAdd.
  ///
  /// In en, this message translates to:
  /// **'Drop to add them'**
  String get dropToAdd;

  /// No description provided for @chooseFiles.
  ///
  /// In en, this message translates to:
  /// **'Choose files'**
  String get chooseFiles;

  /// No description provided for @chooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose the file'**
  String get chooseFile;

  /// No description provided for @uploadsHowItWorks.
  ///
  /// In en, this message translates to:
  /// **'Two upload at a time. If the connection drops, they carry on by themselves. If this page closes, open Uploads again to carry on from where they stopped.'**
  String get uploadsHowItWorks;

  /// No description provided for @namingGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'How to name files'**
  String get namingGuideTitle;

  /// No description provided for @namingGuideIntro.
  ///
  /// In en, this message translates to:
  /// **'Name each file with the VJ first, so files sort and search by VJ, and the upload screen fills everything in:'**
  String get namingGuideIntro;

  /// No description provided for @namingGuideMovie.
  ///
  /// In en, this message translates to:
  /// **'VJ Junior - Commando (1985).mp4'**
  String get namingGuideMovie;

  /// No description provided for @namingGuideEpisode.
  ///
  /// In en, this message translates to:
  /// **'VJ Junior - Prison Break S01E02.mp4'**
  String get namingGuideEpisode;

  /// No description provided for @namingGuideRules.
  ///
  /// In en, this message translates to:
  /// **'\"VJ\" and the VJ\'s name, then \" - \", then the title. A movie\'s year in brackets. An episode\'s season and number as S01E02. Words like HD, 720p and Luganda are ignored.'**
  String get namingGuideRules;

  /// No description provided for @reviewUploadsTitle.
  ///
  /// In en, this message translates to:
  /// **'Check {count, plural, =1{1 file} other{{count} files}} before uploading'**
  String reviewUploadsTitle(int count);

  /// No description provided for @reviewUploadsIntro.
  ///
  /// In en, this message translates to:
  /// **'Each row was filled in from the file\'s name. Change anything that\'s wrong. Choosing a VJ here, then starting, confirms their credit.'**
  String get reviewUploadsIntro;

  /// No description provided for @kind.
  ///
  /// In en, this message translates to:
  /// **'Movie or series'**
  String get kind;

  /// No description provided for @addToSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get addToSeries;

  /// No description provided for @newSeries.
  ///
  /// In en, this message translates to:
  /// **'A new series'**
  String get newSeries;

  /// No description provided for @leaveOut.
  ///
  /// In en, this message translates to:
  /// **'Leave this file out'**
  String get leaveOut;

  /// No description provided for @episodeGoesTo.
  ///
  /// In en, this message translates to:
  /// **'Added to {title}, by {vj}.'**
  String episodeGoesTo(String title, String vj);

  /// No description provided for @reviewUnknownVj.
  ///
  /// In en, this message translates to:
  /// **'The file names {vj}, who isn\'t a VJ here yet. Add them on the draft\'s page once it uploads, or choose a VJ.'**
  String reviewUnknownVj(String vj);

  /// No description provided for @reviewVjCredited.
  ///
  /// In en, this message translates to:
  /// **'This VJ is credited when the draft is made.'**
  String get reviewVjCredited;

  /// No description provided for @reviewNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Give it a title.'**
  String get reviewNeedsTitle;

  /// No description provided for @reviewBadYear.
  ///
  /// In en, this message translates to:
  /// **'The year must be between 1900 and 2100.'**
  String get reviewBadYear;

  /// No description provided for @reviewNeedsEpisode.
  ///
  /// In en, this message translates to:
  /// **'Give the season and episode numbers.'**
  String get reviewNeedsEpisode;

  /// No description provided for @reviewEpisodeExists.
  ///
  /// In en, this message translates to:
  /// **'This series already has season {season}, episode {episode}.'**
  String reviewEpisodeExists(int season, int episode);

  /// No description provided for @reviewEpisodeTwice.
  ///
  /// In en, this message translates to:
  /// **'Season {season}, episode {episode} is in this list twice.'**
  String reviewEpisodeTwice(int season, int episode);

  /// No description provided for @startUploads.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Start the upload} other{Start {count} uploads}}'**
  String startUploads(int count);

  /// No description provided for @uploadsListTitle.
  ///
  /// In en, this message translates to:
  /// **'Uploads'**
  String get uploadsListTitle;

  /// No description provided for @allVjs.
  ///
  /// In en, this message translates to:
  /// **'All VJs'**
  String get allVjs;

  /// No description provided for @clearFinished.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get clearFinished;

  /// No description provided for @uploadsResumedFromDrop.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Carrying on with 1 unfinished upload.} other{Carrying on with {count} unfinished uploads.}}'**
  String uploadsResumedFromDrop(int count);

  /// No description provided for @uploadsNotVideos.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file isn\'t a video, and was left out.} other{{count} files aren\'t videos, and were left out.}}'**
  String uploadsNotVideos(int count);

  /// No description provided for @uploadNeedsFile.
  ///
  /// In en, this message translates to:
  /// **'Needs its file'**
  String get uploadNeedsFile;

  /// No description provided for @uploadQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get uploadQueued;

  /// No description provided for @uploadStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get uploadStarting;

  /// No description provided for @uploadUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get uploadUploading;

  /// No description provided for @uploadPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get uploadPaused;

  /// No description provided for @uploadRetrying.
  ///
  /// In en, this message translates to:
  /// **'Connection lost'**
  String get uploadRetrying;

  /// No description provided for @uploadOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get uploadOffline;

  /// No description provided for @uploadFinished.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get uploadFinished;

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get uploadFailed;

  /// No description provided for @uploadRemoving.
  ///
  /// In en, this message translates to:
  /// **'Removing'**
  String get uploadRemoving;

  /// No description provided for @uploadPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String uploadPercent(int percent);

  /// No description provided for @uploadBytesOf.
  ///
  /// In en, this message translates to:
  /// **'{sent} of {size}'**
  String uploadBytesOf(String sent, String size);

  /// No description provided for @uploadSpeed.
  ///
  /// In en, this message translates to:
  /// **'{speed}/s'**
  String uploadSpeed(String speed);

  /// No description provided for @uploadHoursLeft.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min left'**
  String uploadHoursLeft(int hours, int minutes);

  /// No description provided for @uploadMinutesLeft.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min left'**
  String uploadMinutesLeft(int minutes);

  /// No description provided for @uploadSecondsLeft.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s left'**
  String uploadSecondsLeft(int seconds);

  /// No description provided for @uploadNeedsFileResume.
  ///
  /// In en, this message translates to:
  /// **'Stopped at {percent}% when the page closed. Press Resume to carry on from there.'**
  String uploadNeedsFileResume(int percent);

  /// No description provided for @uploadNeedsFileDrop.
  ///
  /// In en, this message translates to:
  /// **'Stopped at {percent}% when the page closed. Drop or choose {file} again to carry on from there.'**
  String uploadNeedsFileDrop(int percent, String file);

  /// No description provided for @uploadWaitingTurn.
  ///
  /// In en, this message translates to:
  /// **'Waiting its turn.'**
  String get uploadWaitingTurn;

  /// No description provided for @uploadPreparing.
  ///
  /// In en, this message translates to:
  /// **'Making the draft and starting the upload.'**
  String get uploadPreparing;

  /// No description provided for @uploadPausedAt.
  ///
  /// In en, this message translates to:
  /// **'Paused at {percent}%. Nothing is lost.'**
  String uploadPausedAt(int percent);

  /// No description provided for @uploadRetryIn.
  ///
  /// In en, this message translates to:
  /// **'Stopped at {percent}%. Trying again in {seconds} s.'**
  String uploadRetryIn(int percent, int seconds);

  /// No description provided for @uploadWaitingNetwork.
  ///
  /// In en, this message translates to:
  /// **'Stopped at {percent}%. Carries on when the network is back.'**
  String uploadWaitingNetwork(int percent);

  /// No description provided for @uploadDone.
  ///
  /// In en, this message translates to:
  /// **'Uploaded. It is checked and converted next: see its draft.'**
  String get uploadDone;

  /// No description provided for @uploadRemovingPart.
  ///
  /// In en, this message translates to:
  /// **'Stopping, and deleting the part uploaded.'**
  String get uploadRemovingPart;

  /// No description provided for @uploadKeyRefused.
  ///
  /// In en, this message translates to:
  /// **'The server refused the upload key twice. Try again for a new one.'**
  String get uploadKeyRefused;

  /// No description provided for @uploadTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file is larger than 50 GB, VeloraUG\'s limit.'**
  String get uploadTooLarge;

  /// No description provided for @uploadRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server to delete the part uploaded. Remove it again.'**
  String get uploadRemoveFailed;

  /// No description provided for @uploadUnexpected.
  ///
  /// In en, this message translates to:
  /// **'The upload stopped unexpectedly. Try again.'**
  String get uploadUnexpected;

  /// No description provided for @uploadFileChanged.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t the same file: its size or date has changed. Choose the file that was uploading.'**
  String get uploadFileChanged;

  /// No description provided for @uploadFileUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The browser didn\'t give access to the file. Press Resume and allow it, or drop the file again.'**
  String get uploadFileUnreadable;

  /// No description provided for @uploadRestarted.
  ///
  /// In en, this message translates to:
  /// **'The server had lost this upload, so it started again from the beginning.'**
  String get uploadRestarted;

  /// No description provided for @uploadCreditFailed.
  ///
  /// In en, this message translates to:
  /// **'The VJ wasn\'t credited: {reason} Credit them on the draft\'s page.'**
  String uploadCreditFailed(String reason);

  /// No description provided for @uploadProgressLabel.
  ///
  /// In en, this message translates to:
  /// **'Upload of {file}'**
  String uploadProgressLabel(String file);

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @tryNow.
  ///
  /// In en, this message translates to:
  /// **'Try now'**
  String get tryNow;

  /// No description provided for @removeAgain.
  ///
  /// In en, this message translates to:
  /// **'Remove again'**
  String get removeAgain;

  /// No description provided for @openDraft.
  ///
  /// In en, this message translates to:
  /// **'Open draft'**
  String get openDraft;

  /// No description provided for @removeUploadTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this upload?'**
  String get removeUploadTitle;

  /// No description provided for @removeUploadMessage.
  ///
  /// In en, this message translates to:
  /// **'It stops, and the part uploaded is deleted from the server. Its draft stays in Drafts.'**
  String get removeUploadMessage;

  /// No description provided for @quality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get quality;

  /// No description provided for @qualityAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get qualityAuto;

  /// No description provided for @qualityAutoHelp.
  ///
  /// In en, this message translates to:
  /// **'Changes with your connection'**
  String get qualityAutoHelp;

  /// No description provided for @qualityHd.
  ///
  /// In en, this message translates to:
  /// **'HD'**
  String get qualityHd;

  /// No description provided for @qualityNow.
  ///
  /// In en, this message translates to:
  /// **'Quality: {quality}'**
  String qualityNow(String quality);

  /// No description provided for @yourPass.
  ///
  /// In en, this message translates to:
  /// **'Your pass'**
  String get yourPass;

  /// No description provided for @passActiveUntil.
  ///
  /// In en, this message translates to:
  /// **'Your pass runs until {date}.'**
  String passActiveUntil(String date);

  /// No description provided for @passQueuedUntil.
  ///
  /// In en, this message translates to:
  /// **'With the pass you bought next, you can watch until {date}.'**
  String passQueuedUntil(String date);

  /// No description provided for @noPass.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have a pass.'**
  String get noPass;

  /// No description provided for @passIntro.
  ///
  /// In en, this message translates to:
  /// **'A pass lets you watch everything on VeloraUG until it ends. You pay on Pesapal\'s page, by mobile money or card.'**
  String get passIntro;

  /// No description provided for @passChecking.
  ///
  /// In en, this message translates to:
  /// **'A payment is still being checked. It shows here once it has gone through.'**
  String get passChecking;

  /// No description provided for @passCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check your pass.'**
  String get passCouldNotLoad;

  /// No description provided for @buyAPass.
  ///
  /// In en, this message translates to:
  /// **'Buy a pass'**
  String get buyAPass;

  /// No description provided for @buyAnotherPass.
  ///
  /// In en, this message translates to:
  /// **'Buy another pass'**
  String get buyAnotherPass;

  /// No description provided for @choosePass.
  ///
  /// In en, this message translates to:
  /// **'Choose a pass'**
  String get choosePass;

  /// No description provided for @passDay.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get passDay;

  /// No description provided for @passWeek.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get passWeek;

  /// No description provided for @passMonth.
  ///
  /// In en, this message translates to:
  /// **'1 month'**
  String get passMonth;

  /// No description provided for @passDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String passDays(int days);

  /// No description provided for @passPrice.
  ///
  /// In en, this message translates to:
  /// **'UGX {amount}'**
  String passPrice(String amount);

  /// No description provided for @noPassesForSale.
  ///
  /// In en, this message translates to:
  /// **'No passes are for sale right now.'**
  String get noPassesForSale;

  /// No description provided for @phoneForPayment.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneForPayment;

  /// No description provided for @phoneForPaymentHelp.
  ///
  /// In en, this message translates to:
  /// **'Pesapal needs a phone number or an email for your payment.'**
  String get phoneForPaymentHelp;

  /// No description provided for @phoneNotValid.
  ///
  /// In en, this message translates to:
  /// **'Enter a phone number, such as 0772 123 456.'**
  String get phoneNotValid;

  /// No description provided for @payWithPesapal.
  ///
  /// In en, this message translates to:
  /// **'Pay with Pesapal'**
  String get payWithPesapal;

  /// No description provided for @startingPayment.
  ///
  /// In en, this message translates to:
  /// **'Starting your payment'**
  String get startingPayment;

  /// No description provided for @finishPaying.
  ///
  /// In en, this message translates to:
  /// **'Finish paying on Pesapal'**
  String get finishPaying;

  /// No description provided for @finishPayingHelp.
  ///
  /// In en, this message translates to:
  /// **'Pesapal\'s page has opened in a new tab or in your browser. Come back here once you\'ve paid: this page checks by itself.'**
  String get finishPayingHelp;

  /// No description provided for @openPesapalAgain.
  ///
  /// In en, this message translates to:
  /// **'Open Pesapal again'**
  String get openPesapalAgain;

  /// No description provided for @checkAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain;

  /// No description provided for @checkingPayment.
  ///
  /// In en, this message translates to:
  /// **'Checking your payment'**
  String get checkingPayment;

  /// No description provided for @paymentFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'That payment didn\'t go through'**
  String get paymentFailedTitle;

  /// No description provided for @paymentFailedHelp.
  ///
  /// In en, this message translates to:
  /// **'You can try another way to pay on Pesapal\'s page, or choose a pass again.'**
  String get paymentFailedHelp;

  /// No description provided for @paymentGivenUp.
  ///
  /// In en, this message translates to:
  /// **'This payment wasn\'t completed. Choose a pass to try again.'**
  String get paymentGivenUp;

  /// No description provided for @stillWaitingTitle.
  ///
  /// In en, this message translates to:
  /// **'Still waiting for Pesapal'**
  String get stillWaitingTitle;

  /// No description provided for @stillWaitingHelp.
  ///
  /// In en, this message translates to:
  /// **'We haven\'t heard from Pesapal yet. If you paid, your pass shows on the Account tab once it has been checked.'**
  String get stillWaitingHelp;

  /// No description provided for @passReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your pass is ready'**
  String get passReadyTitle;

  /// No description provided for @passReadyUntil.
  ///
  /// In en, this message translates to:
  /// **'You can watch until {date}.'**
  String passReadyUntil(String date);

  /// No description provided for @carryOnWatching.
  ///
  /// In en, this message translates to:
  /// **'Carry on watching'**
  String get carryOnWatching;

  /// No description provided for @passNotForSale.
  ///
  /// In en, this message translates to:
  /// **'This pass isn\'t for sale any more. Choose another.'**
  String get passNotForSale;

  /// No description provided for @paymentsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Payments aren\'t available right now. Try again in a few minutes.'**
  String get paymentsUnavailable;

  /// No description provided for @passSignInNeeded.
  ///
  /// In en, this message translates to:
  /// **'Sign in to buy a pass.'**
  String get passSignInNeeded;

  /// No description provided for @couldNotOpenPesapal.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open Pesapal\'s page. Use Open Pesapal again.'**
  String get couldNotOpenPesapal;

  /// No description provided for @passNeededTitle.
  ///
  /// In en, this message translates to:
  /// **'You need a pass to watch'**
  String get passNeededTitle;

  /// No description provided for @passNeededMessage.
  ///
  /// In en, this message translates to:
  /// **'Buy a pass to watch everything on VeloraUG.'**
  String get passNeededMessage;

  /// No description provided for @passEndedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your pass has ended'**
  String get passEndedTitle;

  /// No description provided for @passEndedMessage.
  ///
  /// In en, this message translates to:
  /// **'Buy another pass to carry on from where you were.'**
  String get passEndedMessage;

  /// No description provided for @passPrices.
  ///
  /// In en, this message translates to:
  /// **'Pass prices'**
  String get passPrices;

  /// No description provided for @passPricesIntro.
  ///
  /// In en, this message translates to:
  /// **'Prices are in Uganda shillings. Leave one empty to stop selling that pass.'**
  String get passPricesIntro;

  /// No description provided for @priceUgx.
  ///
  /// In en, this message translates to:
  /// **'Price for {pass} (UGX)'**
  String priceUgx(String pass);

  /// No description provided for @priceNotValid.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number from 500 to 10,000,000, or leave it empty.'**
  String get priceNotValid;

  /// No description provided for @savePrices.
  ///
  /// In en, this message translates to:
  /// **'Save prices'**
  String get savePrices;

  /// No description provided for @pricesSaved.
  ///
  /// In en, this message translates to:
  /// **'Prices saved.'**
  String get pricesSaved;

  /// No description provided for @choosePlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your plan'**
  String get choosePlanTitle;

  /// No description provided for @choosePlanIntro.
  ///
  /// In en, this message translates to:
  /// **'Every plan unlocks the whole VeloraUG catalogue. Pay once on Pesapal\'s secure page with MTN Mobile Money, Airtel Money or a card. Nothing renews by itself.'**
  String get choosePlanIntro;

  /// No description provided for @mostPopular.
  ///
  /// In en, this message translates to:
  /// **'Most popular'**
  String get mostPopular;

  /// No description provided for @planDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String planDays(int days);

  /// No description provided for @planDevices.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 registered device} other{{count} registered devices}}'**
  String planDevices(int count);

  /// No description provided for @planStreams.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 screen at a time} other{{count} screens at a time}}'**
  String planStreams(int count);

  /// No description provided for @planBenefitCatalogue.
  ///
  /// In en, this message translates to:
  /// **'Every published movie and series'**
  String get planBenefitCatalogue;

  /// No description provided for @planBenefitPlatforms.
  ///
  /// In en, this message translates to:
  /// **'Watch on the web and on Android'**
  String get planBenefitPlatforms;

  /// No description provided for @planBenefitNoRenewal.
  ///
  /// In en, this message translates to:
  /// **'No automatic renewal'**
  String get planBenefitNoRenewal;

  /// No description provided for @payPlan.
  ///
  /// In en, this message translates to:
  /// **'Pay {price}'**
  String payPlan(String price);

  /// No description provided for @planCardLabel.
  ///
  /// In en, this message translates to:
  /// **'{plan}, {price}, {duration}'**
  String planCardLabel(String plan, String price, String duration);

  /// No description provided for @planQueuedNote.
  ///
  /// In en, this message translates to:
  /// **'You have a plan running. A new one starts when it ends, so you keep every day you paid for.'**
  String get planQueuedNote;

  /// No description provided for @paymentSecureNote.
  ///
  /// In en, this message translates to:
  /// **'VeloraUG never sees your mobile money PIN or card number.'**
  String get paymentSecureNote;

  /// No description provided for @tooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a moment and try again.'**
  String get tooManyAttempts;

  /// No description provided for @myMembership.
  ///
  /// In en, this message translates to:
  /// **'My membership'**
  String get myMembership;

  /// No description provided for @membershipActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get membershipActive;

  /// No description provided for @membershipNone.
  ///
  /// In en, this message translates to:
  /// **'No active plan'**
  String get membershipNone;

  /// No description provided for @membershipNoneHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose a plan to start watching everything on VeloraUG.'**
  String get membershipNoneHelp;

  /// No description provided for @membershipChecking.
  ///
  /// In en, this message translates to:
  /// **'Payment being checked'**
  String get membershipChecking;

  /// No description provided for @membershipStarted.
  ///
  /// In en, this message translates to:
  /// **'Started {date}'**
  String membershipStarted(String date);

  /// No description provided for @membershipExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String membershipExpires(String date);

  /// No description provided for @timeLeftDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day left} other{{days} days left}}'**
  String timeLeftDays(int days);

  /// No description provided for @timeLeftHours.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hour left} other{{hours} hours left}}'**
  String timeLeftHours(int hours);

  /// No description provided for @timeLeftMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 minute left} other{{minutes} minutes left}}'**
  String timeLeftMinutes(int minutes);

  /// No description provided for @membershipQueued.
  ///
  /// In en, this message translates to:
  /// **'Next: {plan}, from {date}'**
  String membershipQueued(String plan, String date);

  /// No description provided for @renewPlan.
  ///
  /// In en, this message translates to:
  /// **'Renew'**
  String get renewPlan;

  /// No description provided for @changePlan.
  ///
  /// In en, this message translates to:
  /// **'Change plan'**
  String get changePlan;

  /// No description provided for @choosePlan.
  ///
  /// In en, this message translates to:
  /// **'Choose a plan'**
  String get choosePlan;

  /// No description provided for @myDevices.
  ///
  /// In en, this message translates to:
  /// **'My devices'**
  String get myDevices;

  /// No description provided for @devicesAllowance.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Your plan allows 1 registered device.} other{Your plan allows {count} registered devices.}}'**
  String devicesAllowance(int count);

  /// No description provided for @devicesNone.
  ///
  /// In en, this message translates to:
  /// **'No devices yet. A device registers itself the first time it plays.'**
  String get devicesNone;

  /// No description provided for @devicesOverLimit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Your plan now allows 1 device. Remove the ones you no longer use to keep watching.} other{Your plan now allows {count} devices. Remove the ones you no longer use to keep watching.}}'**
  String devicesOverLimit(int count);

  /// No description provided for @devicesPolicy.
  ///
  /// In en, this message translates to:
  /// **'Removing a device frees its place at once. To stop sharing, up to 3 replacement devices can be added every 30 days.'**
  String get devicesPolicy;

  /// No description provided for @thisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get thisDevice;

  /// No description provided for @lastActive.
  ///
  /// In en, this message translates to:
  /// **'Last active {date}'**
  String lastActive(String date);

  /// No description provided for @removeDevice.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeDevice;

  /// No description provided for @removeDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this device?'**
  String get removeDeviceTitle;

  /// No description provided for @removeDeviceMessage.
  ///
  /// In en, this message translates to:
  /// **'{device} stops playing within a minute. It can register again later, as a new device.'**
  String removeDeviceMessage(String device);

  /// No description provided for @deviceRemovedNotice.
  ///
  /// In en, this message translates to:
  /// **'Device removed.'**
  String get deviceRemovedNotice;

  /// No description provided for @renameDevice.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameDevice;

  /// No description provided for @deviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceName;

  /// No description provided for @deviceRenamed.
  ///
  /// In en, this message translates to:
  /// **'Name saved.'**
  String get deviceRenamed;

  /// No description provided for @platformWeb.
  ///
  /// In en, this message translates to:
  /// **'Web browser'**
  String get platformWeb;

  /// No description provided for @platformAndroid.
  ///
  /// In en, this message translates to:
  /// **'Android'**
  String get platformAndroid;

  /// No description provided for @platformOther.
  ///
  /// In en, this message translates to:
  /// **'Other device'**
  String get platformOther;

  /// No description provided for @devicesCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your devices.'**
  String get devicesCouldNotLoad;

  /// No description provided for @playingNow.
  ///
  /// In en, this message translates to:
  /// **'Playing now'**
  String get playingNow;

  /// No description provided for @playingOn.
  ///
  /// In en, this message translates to:
  /// **'On {device} since {time}'**
  String playingOn(String device, String time);

  /// No description provided for @stopPlayback.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopPlayback;

  /// No description provided for @sessionStoppedNotice.
  ///
  /// In en, this message translates to:
  /// **'Playback stopped on {device}.'**
  String sessionStoppedNotice(String device);

  /// No description provided for @paymentsHeading.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get paymentsHeading;

  /// No description provided for @paymentsNone.
  ///
  /// In en, this message translates to:
  /// **'No payments yet.'**
  String get paymentsNone;

  /// No description provided for @paymentsCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your payments.'**
  String get paymentsCouldNotLoad;

  /// No description provided for @paymentStateCompleted.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paymentStateCompleted;

  /// No description provided for @paymentStatePending.
  ///
  /// In en, this message translates to:
  /// **'Being checked'**
  String get paymentStatePending;

  /// No description provided for @paymentStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get paymentStateFailed;

  /// No description provided for @paymentStateReversed.
  ///
  /// In en, this message translates to:
  /// **'Reversed'**
  String get paymentStateReversed;

  /// No description provided for @paymentStateAbandoned.
  ///
  /// In en, this message translates to:
  /// **'Not completed'**
  String get paymentStateAbandoned;

  /// No description provided for @paymentStateRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get paymentStateRefunded;

  /// No description provided for @paymentReference.
  ///
  /// In en, this message translates to:
  /// **'Ref. {reference}'**
  String paymentReference(String reference);

  /// No description provided for @deviceLimitTitle.
  ///
  /// In en, this message translates to:
  /// **'Device limit reached'**
  String get deviceLimitTitle;

  /// No description provided for @deviceLimitMessage.
  ///
  /// In en, this message translates to:
  /// **'Every device your plan allows is registered. Remove one you no longer use, then try again.'**
  String get deviceLimitMessage;

  /// No description provided for @manageDevices.
  ///
  /// In en, this message translates to:
  /// **'Manage devices'**
  String get manageDevices;

  /// No description provided for @streamLimitTitle.
  ///
  /// In en, this message translates to:
  /// **'Playing on another device'**
  String get streamLimitTitle;

  /// No description provided for @streamLimitMessage.
  ///
  /// In en, this message translates to:
  /// **'Every screen your plan allows is in use. Stop playback on another device to watch here.'**
  String get streamLimitMessage;

  /// No description provided for @stopOnDeviceAndWatch.
  ///
  /// In en, this message translates to:
  /// **'Stop on {device} and watch here'**
  String stopOnDeviceAndWatch(String device);

  /// No description provided for @deviceSwitchLimitMessage.
  ///
  /// In en, this message translates to:
  /// **'This account has added too many new devices in the last 30 days. Keep watching on a registered device, or contact VeloraUG support.'**
  String get deviceSwitchLimitMessage;

  /// No description provided for @sessionEndedTitle.
  ///
  /// In en, this message translates to:
  /// **'Playback stopped'**
  String get sessionEndedTitle;

  /// No description provided for @sessionEndedMessage.
  ///
  /// In en, this message translates to:
  /// **'Playback was stopped from another device, or this device was removed.'**
  String get sessionEndedMessage;

  /// No description provided for @watchHereAgain.
  ///
  /// In en, this message translates to:
  /// **'Watch here again'**
  String get watchHereAgain;

  /// No description provided for @adminSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get adminSubscriptions;

  /// No description provided for @adminOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get adminOverview;

  /// No description provided for @metricActiveSubscribers.
  ///
  /// In en, this message translates to:
  /// **'Active subscribers'**
  String get metricActiveSubscribers;

  /// No description provided for @metricRevenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue, last 30 days'**
  String get metricRevenue;

  /// No description provided for @metricFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed, last 30 days'**
  String get metricFailed;

  /// No description provided for @metricReversed.
  ///
  /// In en, this message translates to:
  /// **'Reversed, last 30 days'**
  String get metricReversed;

  /// No description provided for @metricRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded, last 30 days'**
  String get metricRefunded;

  /// No description provided for @metricPending.
  ///
  /// In en, this message translates to:
  /// **'Being checked now'**
  String get metricPending;

  /// No description provided for @metricDevices.
  ///
  /// In en, this message translates to:
  /// **'Registered devices'**
  String get metricDevices;

  /// No description provided for @metricPlaying.
  ///
  /// In en, this message translates to:
  /// **'Playing now'**
  String get metricPlaying;

  /// No description provided for @adminPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get adminPlans;

  /// No description provided for @adminPlansIntro.
  ///
  /// In en, this message translates to:
  /// **'Prices are in whole Uganda shillings. A change applies to new payments only: what was already bought keeps its price, length and devices. Every change is recorded.'**
  String get adminPlansIntro;

  /// No description provided for @planOnSale.
  ///
  /// In en, this message translates to:
  /// **'On sale'**
  String get planOnSale;

  /// No description provided for @planFeatured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get planFeatured;

  /// No description provided for @planLegacy.
  ///
  /// In en, this message translates to:
  /// **'Legacy pass, kept for history'**
  String get planLegacy;

  /// No description provided for @planSummary.
  ///
  /// In en, this message translates to:
  /// **'{duration} · {devices}'**
  String planSummary(String duration, String devices);

  /// No description provided for @savePlan.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get savePlan;

  /// No description provided for @planSaved.
  ///
  /// In en, this message translates to:
  /// **'{plan} saved.'**
  String planSaved(String plan);

  /// No description provided for @adminPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get adminPayments;

  /// No description provided for @paymentsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get paymentsFilterAll;

  /// No description provided for @adminSubscribers.
  ///
  /// In en, this message translates to:
  /// **'Active subscribers'**
  String get adminSubscribers;

  /// No description provided for @subscribersNone.
  ///
  /// In en, this message translates to:
  /// **'No one has an active plan.'**
  String get subscribersNone;

  /// No description provided for @subscriberLine.
  ///
  /// In en, this message translates to:
  /// **'{plan} until {date} · {devices}'**
  String subscriberLine(String plan, String date, String devices);

  /// No description provided for @adminDevicesOf.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get adminDevicesOf;

  /// No description provided for @markRefunded.
  ///
  /// In en, this message translates to:
  /// **'Mark refunded'**
  String get markRefunded;

  /// No description provided for @markRefundedTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark this payment refunded?'**
  String get markRefundedTitle;

  /// No description provided for @markRefundedMessage.
  ///
  /// In en, this message translates to:
  /// **'Do this only after refunding {amount} in full on Pesapal: Pesapal never tells VeloraUG about refunds. The {plan} pass bought with it ends now for {customer}, and anything playing on it stops. This can\'t be undone.'**
  String markRefundedMessage(String plan, String amount, String customer);

  /// No description provided for @paymentRefundedNotice.
  ///
  /// In en, this message translates to:
  /// **'Marked refunded. Its pass has ended.'**
  String get paymentRefundedNotice;

  /// No description provided for @adminRemoveDeviceMessage.
  ///
  /// In en, this message translates to:
  /// **'{device} stops playing within a minute. The account holder can register it again.'**
  String adminRemoveDeviceMessage(String device);

  /// No description provided for @priceHistory.
  ///
  /// In en, this message translates to:
  /// **'Price history'**
  String get priceHistory;

  /// No description provided for @priceChange.
  ///
  /// In en, this message translates to:
  /// **'{plan}: {from} to {to}'**
  String priceChange(String plan, String from, String to);

  /// No description provided for @noPrice.
  ///
  /// In en, this message translates to:
  /// **'no price'**
  String get noPrice;

  /// The Downloads tab, Android only.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// Screen reader label and tooltip.
  ///
  /// In en, this message translates to:
  /// **'Download season {season}, episode {episode}'**
  String downloadEpisode(int season, int episode);

  /// No description provided for @downloadPreparing.
  ///
  /// In en, this message translates to:
  /// **'Getting the download ready…'**
  String get downloadPreparing;

  /// No description provided for @downloadChooseQuality.
  ///
  /// In en, this message translates to:
  /// **'Download quality'**
  String get downloadChooseQuality;

  /// No description provided for @downloadKeepPhone.
  ///
  /// In en, this message translates to:
  /// **'Saved to your phone\'s Downloads/VeloraUG folder. It\'s yours to keep, and plays in any video player.'**
  String get downloadKeepPhone;

  /// No description provided for @downloadKeepBrowser.
  ///
  /// In en, this message translates to:
  /// **'Your browser saves it to your computer\'s Downloads folder. It\'s yours to keep, and plays in any video player.'**
  String get downloadKeepBrowser;

  /// An estimated download size, such as About 1.2 GB.
  ///
  /// In en, this message translates to:
  /// **'About {size}'**
  String downloadAbout(String size);

  /// No description provided for @sizeGb.
  ///
  /// In en, this message translates to:
  /// **'{size} GB'**
  String sizeGb(String size);

  /// No description provided for @sizeMb.
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String sizeMb(String size);

  /// Shown when Android starts a download.
  ///
  /// In en, this message translates to:
  /// **'Downloading {name}.'**
  String downloadStartedPhone(String name);

  /// Shown when the browser starts a download.
  ///
  /// In en, this message translates to:
  /// **'Your browser is saving {name}.'**
  String downloadStartedBrowser(String name);

  /// No description provided for @downloadCouldNotStart.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the download'**
  String get downloadCouldNotStart;

  /// No description provided for @downloadNotReady.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be downloaded yet. Try again later.'**
  String get downloadNotReady;

  /// No description provided for @downloadNoPermission.
  ///
  /// In en, this message translates to:
  /// **'VeloraUG needs permission to save to your phone\'s storage. Allow it, then try again.'**
  String get downloadNoPermission;

  /// No description provided for @downloadStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Your phone couldn\'t start the download. Try again.'**
  String get downloadStartFailed;

  /// No description provided for @downloadingPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent}%'**
  String downloadingPercent(int percent);

  /// No description provided for @downloadQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting to download'**
  String get downloadQueued;

  /// No description provided for @downloadPaused.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a connection'**
  String get downloadPaused;

  /// No description provided for @downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloaded;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get downloadFailed;

  /// No description provided for @downloadNoRoom.
  ///
  /// In en, this message translates to:
  /// **'Your phone is full. Free up some room, then download it again.'**
  String get downloadNoRoom;

  /// No description provided for @openDownload.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openDownload;

  /// Screen reader label.
  ///
  /// In en, this message translates to:
  /// **'Open {title}'**
  String openDownloadNamed(String title);

  /// No description provided for @openDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'This file can\'t be opened. It may have been deleted, or no app on this phone plays videos.'**
  String get openDownloadFailed;

  /// No description provided for @downloadAgain.
  ///
  /// In en, this message translates to:
  /// **'Download again'**
  String get downloadAgain;

  /// No description provided for @deleteDownload.
  ///
  /// In en, this message translates to:
  /// **'Delete download'**
  String get deleteDownload;

  /// No description provided for @deleteDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this download?'**
  String get deleteDownloadTitle;

  /// No description provided for @deleteDownloadMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} will be deleted from your phone.'**
  String deleteDownloadMessage(String name);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @downloadsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No downloads yet'**
  String get downloadsEmptyTitle;

  /// No description provided for @downloadsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Download movies and episodes to keep them on your phone. Look for Download on a movie or an episode.'**
  String get downloadsEmptyMessage;

  /// No description provided for @downloadsUsed.
  ///
  /// In en, this message translates to:
  /// **'{size} on this phone'**
  String downloadsUsed(String size);

  /// No description provided for @downloadsFolderNote.
  ///
  /// In en, this message translates to:
  /// **'Downloads are saved to your phone\'s Downloads/VeloraUG folder. They\'re yours to keep, and play in any video player, even without VeloraUG.'**
  String get downloadsFolderNote;

  /// Screen reader label for the startup loading ring.
  ///
  /// In en, this message translates to:
  /// **'Starting VeloraUG'**
  String get startingApp;

  /// Navigation destination: narrow the catalogue by type, genre, VJ and language.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// Home shortcut to the Search screen.
  ///
  /// In en, this message translates to:
  /// **'Search titles'**
  String get searchShortcut;

  /// Screen reader label while Home loads its genre, VJ and language rows.
  ///
  /// In en, this message translates to:
  /// **'Loading more rows…'**
  String get loadingMoreShelves;

  /// Filter screen heading.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterHeading;

  /// Filter screen introduction.
  ///
  /// In en, this message translates to:
  /// **'Choose what to show, then see every title that matches.'**
  String get filterIntro;

  /// Filter section: movies, series or both.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get filterType;

  /// Filter choice: movies and series.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// Filter section heading.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get filterGenre;

  /// Filter choice: no genre chosen.
  ///
  /// In en, this message translates to:
  /// **'Any genre'**
  String get filterAnyGenre;

  /// Filter section heading: the VJ who translated the title.
  ///
  /// In en, this message translates to:
  /// **'VJ'**
  String get filterVj;

  /// Filter choice: no VJ chosen.
  ///
  /// In en, this message translates to:
  /// **'Any VJ'**
  String get filterAnyVj;

  /// Filter section heading.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get filterLanguage;

  /// Filter choice: no language chosen.
  ///
  /// In en, this message translates to:
  /// **'Any language'**
  String get filterAnyLanguage;

  /// Button: clears every filter choice.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get filterClear;

  /// Button: shows the titles matching the filter.
  ///
  /// In en, this message translates to:
  /// **'Show results'**
  String get filterShowResults;

  /// Results page title when no filter is chosen.
  ///
  /// In en, this message translates to:
  /// **'All titles'**
  String get filterAllTitles;

  /// Error title when a filter list fails to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load {filter} choices'**
  String filterOptionsFailed(String filter);

  /// Screen reader label while a filter list loads.
  ///
  /// In en, this message translates to:
  /// **'Loading {filter} choices'**
  String filterOptionsLoading(String filter);

  /// Badge on a movie edition's page.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get movieBadge;

  /// Heading above a title's overview.
  ///
  /// In en, this message translates to:
  /// **'Storyline'**
  String get storyline;

  /// Button: shows the whole storyline.
  ///
  /// In en, this message translates to:
  /// **'Read more'**
  String get readMore;

  /// Button: shortens the storyline again.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get readLess;

  /// A download running before its size is known.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get downloadingStarted;

  /// A download Android paused after a failed connection, which it retries by itself.
  ///
  /// In en, this message translates to:
  /// **'Waiting to try again'**
  String get downloadWaitingToRetry;

  /// A download Android paused for another reason.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get downloadPausedOther;

  /// How much of a download has arrived, such as "120 MB of 700 MB".
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String downloadBytesOf(String done, String total);

  /// Downloads group: queued, downloading or paused.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get downloadsInProgress;

  /// Downloads group: finished downloads.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get downloadsCompleted;

  /// Downloads group: downloads that stopped with an error.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get downloadsFailed;

  /// A downloads group heading with how many it has.
  ///
  /// In en, this message translates to:
  /// **'{group} ({count})'**
  String downloadsGroup(String group, int count);

  /// Account row help for Downloads.
  ///
  /// In en, this message translates to:
  /// **'Movies and episodes saved on this phone'**
  String get downloadsRowHelp;

  /// Account group heading.
  ///
  /// In en, this message translates to:
  /// **'Membership'**
  String get membershipGroup;

  /// Account group heading: downloads, history and notifications.
  ///
  /// In en, this message translates to:
  /// **'Your library'**
  String get libraryGroup;

  /// Account group heading: profile, status, settings.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountGroup;

  /// Account row and page title.
  ///
  /// In en, this message translates to:
  /// **'Plans & membership'**
  String get plansTitle;

  /// Account row help for plans.
  ///
  /// In en, this message translates to:
  /// **'Your plan, when it ends, renewing or changing'**
  String get plansRowHelp;

  /// Account row and page title.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get payments;

  /// Account row and page title.
  ///
  /// In en, this message translates to:
  /// **'Watch history'**
  String get historyTitle;

  /// Account row and page title: the in-app inbox.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// Account row and page title.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// Account row and page title.
  ///
  /// In en, this message translates to:
  /// **'Account status'**
  String get accountStatusTitle;

  /// Account row and page title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Account row and page title: deleting the account.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get dangerZoneTitle;

  /// Profile card title: the email used to sign in.
  ///
  /// In en, this message translates to:
  /// **'Sign-in email'**
  String get signInEmail;

  /// Shown on an account page that needs a sign-in.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see this page.'**
  String get signInToSeeThis;

  /// Title on a page that exists only on Android.
  ///
  /// In en, this message translates to:
  /// **'Only in the Android app'**
  String get androidOnlyTitle;

  /// Message on a page that exists only on Android.
  ///
  /// In en, this message translates to:
  /// **'Open VeloraUG on your Android phone to use this.'**
  String get androidOnlyMessage;

  /// Watch history introduction.
  ///
  /// In en, this message translates to:
  /// **'What you watched with this account, latest first.'**
  String get historyIntro;

  /// Watch history empty state title.
  ///
  /// In en, this message translates to:
  /// **'Nothing watched yet'**
  String get historyEmptyTitle;

  /// Watch history empty state message.
  ///
  /// In en, this message translates to:
  /// **'Movies and episodes you watch appear here. Downloads played in your phone\'s own player aren\'t included.'**
  String get historyEmptyMessage;

  /// Watch history error title.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your history'**
  String get historyLoadFailed;

  /// When a title was last watched, such as "Watched 24 Nov 2026, 14:05".
  ///
  /// In en, this message translates to:
  /// **'Watched {when}'**
  String watchedAt(String when);

  /// Notifications introduction.
  ///
  /// In en, this message translates to:
  /// **'Updates about your payments, plan and devices from the last 90 days.'**
  String get notificationsIntro;

  /// Notifications empty state title.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get notificationsEmptyTitle;

  /// Notifications empty state message.
  ///
  /// In en, this message translates to:
  /// **'When something changes on your account, such as a payment going through, it shows here.'**
  String get notificationsEmptyMessage;

  /// Notifications error title.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your notifications'**
  String get notificationsLoadFailed;

  /// How many notifications are unread.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread} other{{count} unread}}'**
  String notificationsUnread(int count);

  /// Button in the notifications inbox.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get markAllRead;

  /// Marks an unread notification.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get unread;

  /// Stands in for a plan name the server didn't give.
  ///
  /// In en, this message translates to:
  /// **'your plan'**
  String get yourPlan;

  /// Stands in for a device name the server didn't give.
  ///
  /// In en, this message translates to:
  /// **'A device'**
  String get aDevice;

  /// Notification title.
  ///
  /// In en, this message translates to:
  /// **'Payment confirmed'**
  String get noticePaymentCompletedTitle;

  /// Notification body.
  ///
  /// In en, this message translates to:
  /// **'Your payment for {plan} went through.'**
  String noticePaymentCompletedBody(String plan);

  /// Notification title.
  ///
  /// In en, this message translates to:
  /// **'Payment refunded'**
  String get noticePaymentRefundedTitle;

  /// Notification body.
  ///
  /// In en, this message translates to:
  /// **'Your payment for {plan} was refunded, and its plan has ended.'**
  String noticePaymentRefundedBody(String plan);

  /// Notification title.
  ///
  /// In en, this message translates to:
  /// **'Plan ending soon'**
  String get noticePassEndingTitle;

  /// Notification body.
  ///
  /// In en, this message translates to:
  /// **'{plan} ends within 3 days. Renew to keep watching.'**
  String noticePassEndingBody(String plan);

  /// Notification title.
  ///
  /// In en, this message translates to:
  /// **'Plan ended'**
  String get noticePassEndedTitle;

  /// Notification body.
  ///
  /// In en, this message translates to:
  /// **'{plan} has ended.'**
  String noticePassEndedBody(String plan);

  /// Notification title.
  ///
  /// In en, this message translates to:
  /// **'Device removed'**
  String get noticeDeviceRemovedTitle;

  /// Notification body.
  ///
  /// In en, this message translates to:
  /// **'{device} was removed from your account by VeloraUG.'**
  String noticeDeviceRemovedBody(String device);

  /// Account status introduction.
  ///
  /// In en, this message translates to:
  /// **'What our systems say about your account. Sign-in and membership are checked separately.'**
  String get accountStatusIntro;

  /// Account status card: the sign-in account.
  ///
  /// In en, this message translates to:
  /// **'Sign-in'**
  String get statusSignIn;

  /// Account status card: the plan.
  ///
  /// In en, this message translates to:
  /// **'Membership'**
  String get statusMembership;

  /// Account status card: a deletion in progress.
  ///
  /// In en, this message translates to:
  /// **'Account deletion'**
  String get statusDeletion;

  /// A value no source could confirm.
  ///
  /// In en, this message translates to:
  /// **'Unknown: couldn\'t be checked'**
  String get statusUnknown;

  /// Sign-in status badge.
  ///
  /// In en, this message translates to:
  /// **'Email verified'**
  String get emailVerified;

  /// Sign-in status badge.
  ///
  /// In en, this message translates to:
  /// **'Email not verified'**
  String get emailNotVerified;

  /// Sign-in status badge when the provider didn't say.
  ///
  /// In en, this message translates to:
  /// **'Email verification unknown'**
  String get emailVerificationUnknown;

  /// Where the sign-in status comes from.
  ///
  /// In en, this message translates to:
  /// **'From your sign-in provider, when you last signed in.'**
  String get statusFromSignIn;

  /// Where the membership status comes from.
  ///
  /// In en, this message translates to:
  /// **'From VeloraUG, now.'**
  String get statusFromVeloraUG;

  /// Account status: the end of the last queued plan.
  ///
  /// In en, this message translates to:
  /// **'Plans bought in advance run until {date}'**
  String membershipRenewsUntil(String date);

  /// Account status badge: a deletion that stopped part way.
  ///
  /// In en, this message translates to:
  /// **'Started, not finished'**
  String get deletionPending;

  /// Account status badge: a finished deletion.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get deletionCompleted;

  /// Settings group heading.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devicesGroup;

  /// Settings group heading.
  ///
  /// In en, this message translates to:
  /// **'Security and notifications'**
  String get securityGroup;

  /// Settings group heading.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutGroup;

  /// Settings row help.
  ///
  /// In en, this message translates to:
  /// **'See and remove the devices signed in to your plan'**
  String get myDevicesRowHelp;

  /// Settings switch: ask for the phone's screen lock or biometrics to open VeloraUG.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLockTitle;

  /// App lock help.
  ///
  /// In en, this message translates to:
  /// **'Ask for your fingerprint, face or phone\'s screen lock to open VeloraUG.'**
  String get appLockHelp;

  /// App lock unavailable.
  ///
  /// In en, this message translates to:
  /// **'Set up a screen lock in your phone settings, then return here and try again.'**
  String get appLockUnavailable;

  /// App lock switch result.
  ///
  /// In en, this message translates to:
  /// **'Not changed: the check was cancelled.'**
  String get appLockNotChanged;

  /// App lock check failed.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t work. Try again.'**
  String get appLockFailed;

  /// App lock check locked out.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Wait a moment, then try again.'**
  String get appLockLockedOut;

  /// App lock check cancelled on the lock screen.
  ///
  /// In en, this message translates to:
  /// **'Cancelled. Tap Unlock to try again.'**
  String get appLockCancelled;

  /// The reason Android's prompt shows when unlocking.
  ///
  /// In en, this message translates to:
  /// **'Unlock VeloraUG'**
  String get appLockReasonUnlock;

  /// The reason Android's prompt shows when turning App lock on.
  ///
  /// In en, this message translates to:
  /// **'Confirm to turn on App lock'**
  String get appLockReasonTurnOn;

  /// The reason Android's prompt shows when turning App lock off.
  ///
  /// In en, this message translates to:
  /// **'Confirm to turn off App lock'**
  String get appLockReasonTurnOff;

  /// Lock screen title.
  ///
  /// In en, this message translates to:
  /// **'VeloraUG is locked'**
  String get appLockLockedTitle;

  /// Lock screen message.
  ///
  /// In en, this message translates to:
  /// **'Use your fingerprint, face or phone\'s screen lock to open it.'**
  String get appLockLockedMessage;

  /// Lock screen button.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get appLockUnlock;

  /// Lock screen button while the prompt shows.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get appLockChecking;

  /// Signs out of the account while the installation stays locked.
  ///
  /// In en, this message translates to:
  /// **'Can\'t unlock? Sign out'**
  String get appLockSignOutInstead;

  /// Settings switch.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get pushTitle;

  /// Push notifications not available in this version.
  ///
  /// In en, this message translates to:
  /// **'VeloraUG can\'t send push notifications yet.'**
  String get pushNotSetUp;

  /// Push notifications on the web.
  ///
  /// In en, this message translates to:
  /// **'Push notifications are only offered in the Android app.'**
  String get pushNotOnWeb;

  /// The phone's notification setting.
  ///
  /// In en, this message translates to:
  /// **'Android allows notifications from VeloraUG.'**
  String get pushOsAllowed;

  /// The phone's notification setting.
  ///
  /// In en, this message translates to:
  /// **'Notifications from VeloraUG are off in Android\'s settings.'**
  String get pushOsBlocked;

  /// The phone's notification setting.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read Android\'s notification setting.'**
  String get pushOsUnknown;

  /// Push notifications help.
  ///
  /// In en, this message translates to:
  /// **'Your inbox in Account › Notifications works either way.'**
  String get pushInboxStillWorks;

  /// Settings row.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get passwordResetTitle;

  /// Settings row help.
  ///
  /// In en, this message translates to:
  /// **'Opens the VeloraUG sign-in page, which emails you a code.'**
  String get passwordResetHelp;

  /// Settings row help when unavailable.
  ///
  /// In en, this message translates to:
  /// **'Password reset isn\'t set up in this version of the app.'**
  String get passwordResetUnavailable;

  /// Settings row.
  ///
  /// In en, this message translates to:
  /// **'Share VeloraUG'**
  String get shareApp;

  /// Text shared with the app link.
  ///
  /// In en, this message translates to:
  /// **'Watch Luganda-translated movies and series on VeloraUG: {link}'**
  String shareAppText(String link);

  /// Snack bar after copying the app link.
  ///
  /// In en, this message translates to:
  /// **'Link copied.'**
  String get shareAppCopied;

  /// Settings row help when unavailable.
  ///
  /// In en, this message translates to:
  /// **'Sharing isn\'t set up in this version of the app.'**
  String get shareAppUnavailable;

  /// Tooltip: copies the app link.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// Settings row.
  ///
  /// In en, this message translates to:
  /// **'Rate on Google Play'**
  String get rateOnPlay;

  /// Settings row help when no listing is set.
  ///
  /// In en, this message translates to:
  /// **'VeloraUG isn\'t on Google Play yet.'**
  String get rateOnPlayUnavailable;

  /// Settings row.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// Settings row help when no policy address is set.
  ///
  /// In en, this message translates to:
  /// **'The privacy policy isn\'t published in the app yet.'**
  String get privacyPolicyUnavailable;

  /// Snack bar when a link fails to open.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link.'**
  String get linkCouldNotOpen;

  /// Danger zone introduction.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your VeloraUG account. This can\'t be undone.'**
  String get dangerZoneIntro;

  /// Danger zone heading.
  ///
  /// In en, this message translates to:
  /// **'What is deleted'**
  String get deletionWhatGoes;

  /// What deletion removes.
  ///
  /// In en, this message translates to:
  /// **'Your profile and display name'**
  String get deletionGoesProfile;

  /// What deletion removes.
  ///
  /// In en, this message translates to:
  /// **'Your watch history and notification read marks'**
  String get deletionGoesHistory;

  /// What deletion removes.
  ///
  /// In en, this message translates to:
  /// **'Your registered devices, and anything playing on them'**
  String get deletionGoesDevices;

  /// What deletion removes.
  ///
  /// In en, this message translates to:
  /// **'Your sign-in account, so you can no longer sign in with it'**
  String get deletionGoesSignIn;

  /// Danger zone heading.
  ///
  /// In en, this message translates to:
  /// **'What is kept'**
  String get deletionWhatStays;

  /// What deletion keeps.
  ///
  /// In en, this message translates to:
  /// **'Records of your payments, which the law and payment checks require'**
  String get deletionStaysPayments;

  /// What deletion keeps.
  ///
  /// In en, this message translates to:
  /// **'Files already downloaded to this phone\'s Downloads folder: they are yours'**
  String get deletionStaysDownloads;

  /// What deletion keeps.
  ///
  /// In en, this message translates to:
  /// **'Time left on a plan is not refunded by deleting'**
  String get deletionStaysPlan;

  /// Danger zone checkbox.
  ///
  /// In en, this message translates to:
  /// **'I understand that my account will be deleted permanently.'**
  String get deletionUnderstand;

  /// Danger zone button.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get deleteAccountButton;

  /// Danger zone button after a deletion stopped part way.
  ///
  /// In en, this message translates to:
  /// **'Finish deleting my account'**
  String get deletionTryAgain;

  /// Danger zone button while deleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting…'**
  String get deletingAccount;

  /// Final confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get deleteAccountConfirmTitle;

  /// Final confirmation message.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be asked to sign in again to confirm it\'s you. Then your account is deleted for good.'**
  String get deleteAccountConfirmMessage;

  /// Final confirmation button.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAccountConfirmButton;

  /// Shown once the server confirms the deletion.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deleted.'**
  String get deletionDone;

  /// Danger zone: a deletion stopped part way.
  ///
  /// In en, this message translates to:
  /// **'A deletion you started didn\'t finish. Nothing more was removed. You can finish it now.'**
  String get deletionPendingHelp;

  /// Danger zone error title.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check account deletion'**
  String get deletionStatusFailed;

  /// Danger zone when the server can't delete accounts.
  ///
  /// In en, this message translates to:
  /// **'Account deletion isn\'t available yet'**
  String get deletionUnavailableTitle;

  /// Danger zone when the server can't delete accounts.
  ///
  /// In en, this message translates to:
  /// **'Deleting an account from the app isn\'t switched on yet. Nothing has been changed.'**
  String get deletionUnavailableMessage;

  /// A deletion that stopped part way.
  ///
  /// In en, this message translates to:
  /// **'Your account couldn\'t be deleted completely. Try again: nothing more is removed until you do.'**
  String get deletionIncompleteMessage;

  /// The server needs a recent sign-in.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to confirm it\'s you.'**
  String get reauthNeeded;

  /// The confirming sign-in was cancelled or failed.
  ///
  /// In en, this message translates to:
  /// **'The sign-in didn\'t finish, so nothing was deleted.'**
  String get reauthFailed;

  /// The confirming sign-in was someone else.
  ///
  /// In en, this message translates to:
  /// **'You signed in with a different account, so nothing was deleted.'**
  String get reauthDifferentAccount;

  /// No description provided for @watchListTitle.
  ///
  /// In en, this message translates to:
  /// **'Watch List'**
  String get watchListTitle;

  /// No description provided for @watchListAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to Watch List'**
  String get watchListAdd;

  /// No description provided for @watchListRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from Watch List'**
  String get watchListRemove;

  /// No description provided for @watchListRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry Watch List'**
  String get watchListRetry;

  /// No description provided for @watchListLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your Watch List'**
  String get watchListLoadFailed;

  /// No description provided for @watchListEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your Watch List is empty'**
  String get watchListEmpty;

  /// No description provided for @watchListEmptyHelp.
  ///
  /// In en, this message translates to:
  /// **'Add movies or episodes to watch later.'**
  String get watchListEmptyHelp;

  /// No description provided for @reuseMovieDetails.
  ///
  /// In en, this message translates to:
  /// **'Use details from another movie'**
  String get reuseMovieDetails;

  /// No description provided for @reuseMovieSearchHelp.
  ///
  /// In en, this message translates to:
  /// **'Search published movies by title. Try the title without its part number.'**
  String get reuseMovieSearchHelp;

  /// No description provided for @reuseMovieQueryLength.
  ///
  /// In en, this message translates to:
  /// **'Enter 2 to 120 characters to search.'**
  String get reuseMovieQueryLength;

  /// No description provided for @reuseMovieNoResults.
  ///
  /// In en, this message translates to:
  /// **'No published movies match that title.'**
  String get reuseMovieNoResults;

  /// No description provided for @reuseMovieConfirm.
  ///
  /// In en, this message translates to:
  /// **'Choose a movie to share its details. Its poster and VJ credit fill any empty fields. Your title and video stay as they are.'**
  String get reuseMovieConfirm;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
