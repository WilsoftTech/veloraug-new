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
