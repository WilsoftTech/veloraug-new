// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'VeloraUG';

  @override
  String get home => 'Home';

  @override
  String get search => 'Search';

  @override
  String get account => 'Account';

  @override
  String get admin => 'Admin';

  @override
  String get loading => 'Loading…';

  @override
  String get loadingMore => 'Loading more…';

  @override
  String get tryAgain => 'Try again';

  @override
  String get back => 'Back';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved.';

  @override
  String get saving => 'Saving…';

  @override
  String get done => 'Done';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied.';

  @override
  String get refresh => 'Refresh';

  @override
  String get remove => 'Remove';

  @override
  String get required => 'Required.';

  @override
  String get showMore => 'Show more';

  @override
  String get seeAll => 'See all';

  @override
  String seeAllOf(String row) {
    return 'See all of $row';
  }

  @override
  String get busy => 'VeloraUG is busy right now. Try again in a moment.';

  @override
  String get unreachable =>
      'Couldn\'t reach VeloraUG. Check your connection and try again.';

  @override
  String get somethingWentWrong => 'Something went wrong. Try again.';

  @override
  String get notAvailable => 'This isn\'t available.';

  @override
  String get noApiAddress => 'This version of the app can\'t reach VeloraUG.';

  @override
  String get signInNotAccepted =>
      'VeloraUG didn\'t accept your sign-in. Sign out, then sign in again.';

  @override
  String numberBetween(int min, int max) {
    return 'Use a whole number from $min to $max.';
  }

  @override
  String tooLong(int max) {
    return 'Use $max characters or fewer.';
  }

  @override
  String get password => 'Password';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get searchLabel => 'Search titles and VJs';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get homeHeading => 'Welcome to VeloraUG';

  @override
  String get homeIntro =>
      'Movies and series translated into Luganda by Uganda\'s VJs.';

  @override
  String get catalogueNotSetUpTitle => 'The catalogue isn\'t set up';

  @override
  String get catalogueNotSetUpMessage =>
      'This version of the app has no address for VeloraUG\'s service, so it has nothing to show.';

  @override
  String get homeLoadFailed => 'Couldn\'t load the catalogue';

  @override
  String get listLoadFailed => 'Couldn\'t load this list';

  @override
  String get nothingYetTitle => 'Nothing to watch yet';

  @override
  String get nothingHereTitle => 'Nothing here yet';

  @override
  String get nothingYetMessage =>
      'New movies and series will appear here as soon as they are added.';

  @override
  String get latest => 'Latest';

  @override
  String get movies => 'Movies';

  @override
  String get series => 'Series';

  @override
  String get movie => 'Movie';

  @override
  String get seriesBadge => 'Series';

  @override
  String inLanguage(String language) {
    return 'In $language';
  }

  @override
  String get loadingTitles => 'Loading titles';

  @override
  String get loadingVj => 'Loading the VJ';

  @override
  String get vjNotFoundTitle => 'This VJ isn\'t available';

  @override
  String get vjNotFoundMessage =>
      'They may have nothing published yet. Go back to find something else to watch.';

  @override
  String get vjLoadFailed => 'Couldn\'t load this VJ';

  @override
  String get vjNoBio => 'No biography yet.';

  @override
  String get loadingEdition => 'Loading the title';

  @override
  String get editionNotFoundTitle => 'This title isn\'t available';

  @override
  String get editionNotFoundMessage =>
      'It may have been removed from VeloraUG. Go back to find something else to watch.';

  @override
  String get editionLoadFailed => 'Couldn\'t load this title';

  @override
  String editionLabelLink(String label) {
    return '$label. Opens the VJ\'s page.';
  }

  @override
  String alsoKnownAs(String title) {
    return 'Original title: $title';
  }

  @override
  String runtimeMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String runtimeHours(int hours) {
    return '$hours h';
  }

  @override
  String runtimeHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get trailer => 'Trailer';

  @override
  String get watch => 'Watch';

  @override
  String get signInToWatchButton => 'Sign in to watch';

  @override
  String get signInFirst => 'Sign in first';

  @override
  String get notAvailableHere => 'Not available here';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get episodes => 'Episodes';

  @override
  String get noEpisodesTitle => 'No episodes yet';

  @override
  String get noEpisodesMessage =>
      'Episodes will appear here as soon as they are added.';

  @override
  String seasonNumber(int season) {
    return 'Season $season';
  }

  @override
  String episodeNumber(int episode) {
    return 'Episode $episode';
  }

  @override
  String playEpisode(int season, int episode) {
    return 'Play season $season, episode $episode';
  }

  @override
  String get gettingReady => 'Getting the video ready';

  @override
  String get couldNotPlay => 'Couldn\'t play this';

  @override
  String get playbackStopped =>
      'Playback stopped. Check your connection, then try again from where you were.';

  @override
  String episodeHeading(String title, int season, int episode) {
    return '$title · S$season E$episode';
  }

  @override
  String get nextEpisode => 'Next episode';

  @override
  String nextEpisodeOf(int season, int episode) {
    return 'Next episode: season $season, episode $episode';
  }

  @override
  String upNext(int season, int episode) {
    return 'Up next: S$season E$episode';
  }

  @override
  String get loadingVideo => 'Loading the video';

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Play';

  @override
  String get position => 'Position';

  @override
  String get signInToWatch => 'Sign in to watch.';

  @override
  String get notReadyToWatch => 'This can\'t be watched yet.';

  @override
  String get adminOnly => 'This account isn\'t an admin.';

  @override
  String get searchHeading => 'Search';

  @override
  String get searchIdleTitle => 'Find a movie, series or VJ';

  @override
  String searchIdleMessage(int count) {
    return 'Type at least $count letters of a title or a VJ\'s name.';
  }

  @override
  String get searchFailed => 'Couldn\'t search';

  @override
  String get searchNoneTitle => 'Nothing matches';

  @override
  String searchNoneMessage(String query) {
    return 'No title or VJ in VeloraUG matches \"$query\".';
  }

  @override
  String searchResultCount(int count, String query) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results for \"$query\"',
      one: '1 result for \"$query\"',
    );
    return '$_temp0';
  }

  @override
  String searchResultsFor(String query) {
    return 'Results for \"$query\"';
  }

  @override
  String get signedOutTitle => 'You\'re signed out';

  @override
  String get signedInTitle => 'You\'re signed in';

  @override
  String get signInNotSetUp =>
      'Sign-in isn\'t set up in this version of the app.';

  @override
  String get checkingSignIn => 'Checking your sign-in';

  @override
  String get takesAMoment => 'This takes a moment.';

  @override
  String get signInExplained =>
      'Sign in, or create an account, on the VeloraUG sign-in page. It opens in your browser.';

  @override
  String get signIn => 'Sign in';

  @override
  String get signOut => 'Sign out';

  @override
  String get waitingForSignIn => 'Waiting for the sign-in page…';

  @override
  String get signingOut => 'Signing out…';

  @override
  String signedInAs(String email) {
    return 'Signed in as $email.';
  }

  @override
  String get signedInOnDevice => 'Your account is signed in on this device.';

  @override
  String get signInCancelled =>
      'Sign-in was cancelled, so you\'re still signed out.';

  @override
  String get signInBrowserFailed =>
      'The sign-in page couldn\'t open. Check that a browser is available, and on the web that pop-ups are allowed, then try again.';

  @override
  String get signInDenied =>
      'You didn\'t allow VeloraUG to use your account, so you\'re still signed out.';

  @override
  String get signInTimedOut =>
      'The sign-in timed out. Press Sign in to start again.';

  @override
  String get signInNetwork =>
      'VeloraUG couldn\'t reach the sign-in service. Check your connection and try again.';

  @override
  String get signInUnverified =>
      'The sign-in couldn\'t be verified, so it was stopped. Please try again.';

  @override
  String get signInTryAgain => 'The sign-in didn\'t finish. Please try again.';

  @override
  String get sessionEnded =>
      'Your sign-in has ended. Sign in again to continue.';

  @override
  String get signedOutNotice => 'You\'re signed out.';

  @override
  String get signedOutOffline =>
      'You\'re signed out on this device. VeloraUG couldn\'t reach the sign-in service, so the browser may still remember you. On a shared device, sign in and out again when you are online.';

  @override
  String get signedOutBrowserKept =>
      'You\'re signed out on this device, but the browser sign-out didn\'t finish, so the browser may still remember you. On a shared device, sign in and out again.';

  @override
  String get credits => 'Credits';

  @override
  String get aboutTmdb =>
      'Movie and series titles, descriptions and images come from TMDB, The Movie Database.';

  @override
  String get tmdbLogo => 'TMDB logo';

  @override
  String get tmdbNotice =>
      'This product uses the TMDB API but is not endorsed or certified by TMDB.';

  @override
  String get yourProfile => 'Your profile';

  @override
  String get loadingProfile => 'Loading your profile…';

  @override
  String get noDisplayName => 'You haven\'t set a display name yet.';

  @override
  String displayNameIs(String name) {
    return 'Your display name is $name.';
  }

  @override
  String get displayName => 'Display name';

  @override
  String displayNameHelp(int max) {
    return 'Up to $max characters. Leave it empty to remove it.';
  }

  @override
  String nameTooLong(int max) {
    return 'Use $max characters or fewer.';
  }

  @override
  String get nameRemoved => 'Your name was removed.';

  @override
  String get saveName => 'Save name';

  @override
  String get profileSignedOut => 'Sign in to see your profile.';

  @override
  String get profileInvalidName => 'Use 1 to 80 characters for your name.';

  @override
  String get adminNotSetUp =>
      'The admin screens aren\'t set up in this version of the app.';

  @override
  String get adminSignedOut => 'Sign in as an admin to do this.';

  @override
  String get adminNotFound =>
      'That no longer exists. Refresh to see the latest.';

  @override
  String get adminConflict => 'That can\'t be done right now.';

  @override
  String get adminInvalid => 'VeloraUG refused that.';

  @override
  String get adminBadImage => 'Use a JPEG, PNG or WebP image of at most 2 MB.';

  @override
  String get adminLoadFailed => 'Couldn\'t load this';

  @override
  String get adminDrafts => 'Drafts';

  @override
  String get adminVjs => 'VJs';

  @override
  String get adminSettings => 'Settings';

  @override
  String get statusDraft => 'Draft';

  @override
  String get statusPublished => 'Published';

  @override
  String get statusHidden => 'Hidden';

  @override
  String get testFilm => 'Test film';

  @override
  String get noVjYet => 'No VJ yet';

  @override
  String get needed => 'Needed';

  @override
  String get adminDraftsIntro =>
      'Drafts, hidden titles, and series with new episodes waiting. Each says what it still needs.';

  @override
  String get newDraft => 'New draft';

  @override
  String get noDraftsTitle => 'No drafts';

  @override
  String get noDraftsMessage =>
      'Start a draft for each translated movie or series, then upload its video with the key it gives you.';

  @override
  String stillNeeds(String list) {
    return 'Still needs: $list';
  }

  @override
  String episodesWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes waiting for approval',
      one: '1 episode waiting for approval',
    );
    return '$_temp0';
  }

  @override
  String get readyToPublish => 'Ready to publish.';

  @override
  String get newDraftIntro =>
      'Give the title as the VJ\'s edition is known. Details, poster and VJ credit come after the video is uploaded.';

  @override
  String get titleAsSubmitted => 'Title';

  @override
  String get titleAsSubmittedHelp =>
      'Shown to viewers. TMDB is searched with it.';

  @override
  String get language => 'Language';

  @override
  String get yearOptional => 'Year (optional)';

  @override
  String get season => 'Season';

  @override
  String get episode => 'Episode';

  @override
  String get episodeTitleOptional => 'Episode title (optional)';

  @override
  String get startDraft => 'Start draft';

  @override
  String get uploadKeyTitle => 'Upload key';

  @override
  String get uploadKeyOnce =>
      'Copy this key now. It is shown only once, and VeloraUG doesn\'t keep it.';

  @override
  String uploadKeyExpires(String date) {
    return 'It works until $date, for one upload.';
  }

  @override
  String get uploadKeyHowTo =>
      'Upload the video with: python tools/veloraug_upload.py <file>, and paste the key when asked.';

  @override
  String get draft => 'Draft';

  @override
  String get renameTitle => 'Change the title';

  @override
  String get displayTitle => 'Title shown to viewers';

  @override
  String get video => 'Video';

  @override
  String get videosIntro =>
      'Preview each video before confirming its VJ credit.';

  @override
  String get addEpisode => 'Add episode';

  @override
  String get movieVideo => 'The movie';

  @override
  String episodeShort(int season, int episode) {
    return 'S$season E$episode';
  }

  @override
  String get approved => 'Approved';

  @override
  String get waitingApproval => 'Waiting for approval';

  @override
  String fileName(String name) {
    return 'File: $name';
  }

  @override
  String fileTags(String tags) {
    return 'Tags: $tags';
  }

  @override
  String get preview => 'Preview';

  @override
  String get approveEpisode => 'Approve episode';

  @override
  String get episodeApproved => 'Episode approved. Viewers can now watch it.';

  @override
  String get newUploadKey => 'New upload key';

  @override
  String get keyLabel => 'Who it\'s for';

  @override
  String get keyLabelHelp =>
      'A name to tell keys apart, such as \"Owner\" or \"Better copy\".';

  @override
  String get keyLabelDefault => 'Owner';

  @override
  String keyLine(String label, String date) {
    return 'Key \"$label\", unused, until $date';
  }

  @override
  String get revoke => 'Revoke';

  @override
  String get revokeKeyTitle => 'Revoke this key?';

  @override
  String revokeKeyMessage(String label) {
    return 'The key \"$label\" will stop working at once.';
  }

  @override
  String get keyRevoked => 'Key revoked.';

  @override
  String get videoNone => 'Not uploaded';

  @override
  String get videoUploading => 'Uploading';

  @override
  String get videoChecking => 'Checking';

  @override
  String get videoConverting => 'Converting';

  @override
  String get videoReady => 'Ready';

  @override
  String get videoRefused => 'Refused';

  @override
  String get videoFailed => 'Failed';

  @override
  String get videoRemoved => 'Removed';

  @override
  String get details => 'Details';

  @override
  String get lookupWaiting => 'TMDB is searched once the video is ready.';

  @override
  String get lookupClear => 'TMDB found a clear match, filled in below.';

  @override
  String get lookupChoose =>
      'TMDB found several possible titles. Choose the right one.';

  @override
  String get lookupNone =>
      'TMDB found nothing. Search again with another title, give a TMDB ID, or type the details in.';

  @override
  String get lookupFailed =>
      'TMDB couldn\'t be reached. Search again, or type the details in.';

  @override
  String get lookupChosen => 'Details chosen from TMDB.';

  @override
  String get lookupManual => 'Details typed in.';

  @override
  String tmdbId(int id) {
    return 'TMDB $id';
  }

  @override
  String get useThis => 'Use this';

  @override
  String get searchTmdbAgain => 'Search TMDB again';

  @override
  String get titleToSearch => 'Title to search';

  @override
  String get titleToSearchHelp =>
      'Without the VJ\'s name or words like \"translated\".';

  @override
  String get useTmdbId => 'Use a TMDB ID';

  @override
  String get tmdbIdLabel => 'TMDB ID';

  @override
  String get tmdbIdHelpMovie =>
      'The number in the movie\'s address on themoviedb.org.';

  @override
  String get tmdbIdHelpSeries =>
      'The number in the series\' address on themoviedb.org.';

  @override
  String get typeDetails => 'Type the details in';

  @override
  String get originalTitle => 'Original title';

  @override
  String get runtimeOptional => 'Length in minutes (optional)';

  @override
  String get genresOptional => 'Genres (optional)';

  @override
  String get genresHelp => 'Separated by commas, such as: Action, Drama';

  @override
  String get overviewOptional => 'Description (optional)';

  @override
  String get poster => 'Poster';

  @override
  String get showTmdbPosters => 'Show TMDB\'s posters';

  @override
  String get uploadPoster => 'Upload a poster';

  @override
  String get noTmdbPosters =>
      'TMDB has no English posters for this title. Upload one instead.';

  @override
  String get choosePoster => 'Use this poster';

  @override
  String get posterUploaded => 'Poster uploaded and chosen.';

  @override
  String get imageTooBig => 'That image is over 2 MB. Use a smaller one.';

  @override
  String get vjCredit => 'VJ credit';

  @override
  String get creditIntro =>
      'Nothing is credited until you confirm it. Preview the video first: a wrong credit is a real harm to a VJ.';

  @override
  String creditedTo(String name) {
    return 'Credited to $name.';
  }

  @override
  String get suggestions => 'Suggested from the file';

  @override
  String get noSuggestions =>
      'The file names no known VJ. Choose one, or add a new VJ.';

  @override
  String suggestionLine(String name, String foundIn) {
    return '$name, found in $foundIn';
  }

  @override
  String get creditThisVj => 'Credit this VJ';

  @override
  String addAndCredit(String name) {
    return 'Add $name and credit them';
  }

  @override
  String get chooseVj => 'Choose a VJ';

  @override
  String get addNewVj => 'Add a new VJ';

  @override
  String get vjName => 'VJ\'s name';

  @override
  String get confirmCreditTitle => 'Confirm the VJ credit';

  @override
  String confirmCreditMessage(String name, String title) {
    return 'Credit $name for \"$title\"? Confirm only after previewing the video.';
  }

  @override
  String get confirmCredit => 'Confirm credit';

  @override
  String get missingVideo => 'a ready video';

  @override
  String get missingDetails => 'details, from TMDB or typed in';

  @override
  String get missingPoster => 'a chosen poster';

  @override
  String get missingCredit => 'a confirmed VJ credit';

  @override
  String get publishing => 'Publishing';

  @override
  String get cantPublishYet => 'This can\'t be published yet. It still needs:';

  @override
  String get publishedExplained =>
      'Viewers can see this. New episodes wait for your approval.';

  @override
  String get publish => 'Publish';

  @override
  String get publishedNow => 'Published. Viewers can now see it.';

  @override
  String get hide => 'Hide';

  @override
  String get hideTitle => 'Hide this title?';

  @override
  String get hideMessage =>
      'Viewers won\'t see it, and anyone watching it is stopped. You can publish it again later.';

  @override
  String get hiddenNow => 'Hidden from viewers.';

  @override
  String get adminVjsIntro =>
      'Every VJ, published or not. Other spellings help suggest the credit from a file\'s name.';

  @override
  String get addVj => 'Add a VJ';

  @override
  String get editVj => 'Change this VJ';

  @override
  String get noVjsTitle => 'No VJs yet';

  @override
  String get noVjsMessage => 'Add a VJ here, or while confirming a credit.';

  @override
  String publishedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count published',
      one: '1 published',
      zero: 'Nothing published',
    );
    return '$_temp0';
  }

  @override
  String alsoSpelled(String names) {
    return 'Also: $names';
  }

  @override
  String get uploadPhoto => 'Upload a photo';

  @override
  String get photoUploaded => 'Photo uploaded.';

  @override
  String get photoAfterAdding => 'Add the VJ first, then their photo.';

  @override
  String get vjNameHelp =>
      'As viewers know them, such as \"VJ Junior\". Shown on posters.';

  @override
  String get otherSpellings => 'Other spellings (optional)';

  @override
  String get otherSpellingsHelp =>
      'Separated by commas, as they appear in file names.';

  @override
  String get bio => 'Biography (optional)';

  @override
  String get admins => 'Admins';

  @override
  String get adminsIntro =>
      'Admins can publish titles and add or remove other admins. The last admin can\'t be removed.';

  @override
  String addedOn(String date) {
    return 'Added on $date';
  }

  @override
  String addedByOn(String email, String date) {
    return 'Added by $email on $date';
  }

  @override
  String get lastAdmin => 'Last admin';

  @override
  String get adminEmail => 'Email of the new admin';

  @override
  String get adminEmailHelp =>
      'They must have signed in to VeloraUG once, and confirmed this email.';

  @override
  String get enterEmail => 'Enter an email address.';

  @override
  String get addAdmin => 'Add admin';

  @override
  String adminAdded(String email) {
    return '$email is now an admin.';
  }

  @override
  String adminRemoved(String who) {
    return '$who is no longer an admin.';
  }

  @override
  String get removeAdminTitle => 'Remove this admin?';

  @override
  String removeAdminMessage(String who) {
    return '$who will no longer see the admin screens.';
  }

  @override
  String get languages => 'Languages';

  @override
  String get languagesIntro =>
      'Editions can be in any of these. Browsing by language appears once a second language has something published.';

  @override
  String get languageCode => 'Language code';

  @override
  String get languageCodeHelp =>
      'Two or three letters, such as \"nyn\" for Runyankole.';

  @override
  String get languageCodeInvalid => 'Use two or three letters.';

  @override
  String get languageName => 'Language name';

  @override
  String get addLanguage => 'Add language';

  @override
  String languageAdded(String name) {
    return '$name added.';
  }

  @override
  String get adminUploads => 'Uploads';

  @override
  String get adminUploadsIntro =>
      'Upload videos from this browser. Each file becomes a draft, or an episode of a series, and carries on after a lost connection, a closed tab or a power cut.';

  @override
  String get uploadsNotSetUpTitle => 'Uploading isn\'t set up';

  @override
  String get uploadsNotSetUpMessage =>
      'This build has no upload address. Upload with tools/veloraug_upload.py instead, or set UPLOAD_BASE_URL.';

  @override
  String get dropVideosHere => 'Drag video files here';

  @override
  String get dropToAdd => 'Drop to add them';

  @override
  String get chooseFiles => 'Choose files';

  @override
  String get chooseFile => 'Choose the file';

  @override
  String get uploadsHowItWorks =>
      'Two upload at a time. If the connection drops, they carry on by themselves. If this page closes, open Uploads again to carry on from where they stopped.';

  @override
  String get namingGuideTitle => 'How to name files';

  @override
  String get namingGuideIntro =>
      'Name each file with the VJ first, so files sort and search by VJ, and the upload screen fills everything in:';

  @override
  String get namingGuideMovie => 'VJ Junior - Commando (1985).mp4';

  @override
  String get namingGuideEpisode => 'VJ Junior - Prison Break S01E02.mp4';

  @override
  String get namingGuideRules =>
      '\"VJ\" and the VJ\'s name, then \" - \", then the title. A movie\'s year in brackets. An episode\'s season and number as S01E02. Words like HD, 720p and Luganda are ignored.';

  @override
  String reviewUploadsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return 'Check $_temp0 before uploading';
  }

  @override
  String get reviewUploadsIntro =>
      'Each row was filled in from the file\'s name. Change anything that\'s wrong. Choosing a VJ here, then starting, confirms their credit.';

  @override
  String get kind => 'Movie or series';

  @override
  String get addToSeries => 'Series';

  @override
  String get newSeries => 'A new series';

  @override
  String get leaveOut => 'Leave this file out';

  @override
  String episodeGoesTo(String title, String vj) {
    return 'Added to $title, by $vj.';
  }

  @override
  String reviewUnknownVj(String vj) {
    return 'The file names $vj, who isn\'t a VJ here yet. Add them on the draft\'s page once it uploads, or choose a VJ.';
  }

  @override
  String get reviewVjCredited => 'This VJ is credited when the draft is made.';

  @override
  String get reviewNeedsTitle => 'Give it a title.';

  @override
  String get reviewBadYear => 'The year must be between 1900 and 2100.';

  @override
  String get reviewNeedsEpisode => 'Give the season and episode numbers.';

  @override
  String reviewEpisodeExists(int season, int episode) {
    return 'This series already has season $season, episode $episode.';
  }

  @override
  String reviewEpisodeTwice(int season, int episode) {
    return 'Season $season, episode $episode is in this list twice.';
  }

  @override
  String startUploads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Start $count uploads',
      one: 'Start the upload',
    );
    return '$_temp0';
  }

  @override
  String get uploadsListTitle => 'Uploads';

  @override
  String get allVjs => 'All VJs';

  @override
  String get clearFinished => 'Clear finished';

  @override
  String uploadsResumedFromDrop(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Carrying on with $count unfinished uploads.',
      one: 'Carrying on with 1 unfinished upload.',
    );
    return '$_temp0';
  }

  @override
  String uploadsNotVideos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files aren\'t videos, and were left out.',
      one: '1 file isn\'t a video, and was left out.',
    );
    return '$_temp0';
  }

  @override
  String get uploadNeedsFile => 'Needs its file';

  @override
  String get uploadQueued => 'Waiting';

  @override
  String get uploadStarting => 'Starting';

  @override
  String get uploadUploading => 'Uploading';

  @override
  String get uploadPaused => 'Paused';

  @override
  String get uploadRetrying => 'Connection lost';

  @override
  String get uploadOffline => 'Offline';

  @override
  String get uploadFinished => 'Uploaded';

  @override
  String get uploadFailed => 'Stopped';

  @override
  String get uploadRemoving => 'Removing';

  @override
  String uploadPercent(int percent) {
    return '$percent%';
  }

  @override
  String uploadBytesOf(String sent, String size) {
    return '$sent of $size';
  }

  @override
  String uploadSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String uploadHoursLeft(int hours, int minutes) {
    return '$hours h $minutes min left';
  }

  @override
  String uploadMinutesLeft(int minutes) {
    return '$minutes min left';
  }

  @override
  String uploadSecondsLeft(int seconds) {
    return '$seconds s left';
  }

  @override
  String uploadNeedsFileResume(int percent) {
    return 'Stopped at $percent% when the page closed. Press Resume to carry on from there.';
  }

  @override
  String uploadNeedsFileDrop(int percent, String file) {
    return 'Stopped at $percent% when the page closed. Drop or choose $file again to carry on from there.';
  }

  @override
  String get uploadWaitingTurn => 'Waiting its turn.';

  @override
  String get uploadPreparing => 'Making the draft and starting the upload.';

  @override
  String uploadPausedAt(int percent) {
    return 'Paused at $percent%. Nothing is lost.';
  }

  @override
  String uploadRetryIn(int percent, int seconds) {
    return 'Stopped at $percent%. Trying again in $seconds s.';
  }

  @override
  String uploadWaitingNetwork(int percent) {
    return 'Stopped at $percent%. Carries on when the network is back.';
  }

  @override
  String get uploadDone =>
      'Uploaded. It is checked and converted next: see its draft.';

  @override
  String get uploadRemovingPart => 'Stopping, and deleting the part uploaded.';

  @override
  String get uploadKeyRefused =>
      'The server refused the upload key twice. Try again for a new one.';

  @override
  String get uploadTooLarge =>
      'The file is larger than 50 GB, VeloraUG\'s limit.';

  @override
  String get uploadRemoveFailed =>
      'Couldn\'t reach the server to delete the part uploaded. Remove it again.';

  @override
  String get uploadUnexpected => 'The upload stopped unexpectedly. Try again.';

  @override
  String get uploadFileChanged =>
      'That isn\'t the same file: its size or date has changed. Choose the file that was uploading.';

  @override
  String get uploadFileUnreadable =>
      'The browser didn\'t give access to the file. Press Resume and allow it, or drop the file again.';

  @override
  String get uploadRestarted =>
      'The server had lost this upload, so it started again from the beginning.';

  @override
  String uploadCreditFailed(String reason) {
    return 'The VJ wasn\'t credited: $reason Credit them on the draft\'s page.';
  }

  @override
  String uploadProgressLabel(String file) {
    return 'Upload of $file';
  }

  @override
  String get resume => 'Resume';

  @override
  String get tryNow => 'Try now';

  @override
  String get removeAgain => 'Remove again';

  @override
  String get openDraft => 'Open draft';

  @override
  String get removeUploadTitle => 'Remove this upload?';

  @override
  String get removeUploadMessage =>
      'It stops, and the part uploaded is deleted from the server. Its draft stays in Drafts.';

  @override
  String get quality => 'Quality';

  @override
  String get qualityAuto => 'Auto';

  @override
  String get qualityAutoHelp => 'Changes with your connection';

  @override
  String get qualityHd => 'HD';

  @override
  String qualityNow(String quality) {
    return 'Quality: $quality';
  }

  @override
  String get yourPass => 'Your pass';

  @override
  String passActiveUntil(String date) {
    return 'Your pass runs until $date.';
  }

  @override
  String passQueuedUntil(String date) {
    return 'With the pass you bought next, you can watch until $date.';
  }

  @override
  String get noPass => 'You don\'t have a pass.';

  @override
  String get passIntro =>
      'A pass lets you watch everything on VeloraUG until it ends. You pay on Pesapal\'s page, by mobile money or card.';

  @override
  String get passChecking =>
      'A payment is still being checked. It shows here once it has gone through.';

  @override
  String get passCouldNotLoad => 'Couldn\'t check your pass.';

  @override
  String get buyAPass => 'Buy a pass';

  @override
  String get buyAnotherPass => 'Buy another pass';

  @override
  String get choosePass => 'Choose a pass';

  @override
  String get passDay => '1 day';

  @override
  String get passWeek => '1 week';

  @override
  String get passMonth => '1 month';

  @override
  String passDays(int days) {
    return '$days days';
  }

  @override
  String passPrice(String amount) {
    return 'UGX $amount';
  }

  @override
  String get noPassesForSale => 'No passes are for sale right now.';

  @override
  String get phoneForPayment => 'Phone number';

  @override
  String get phoneForPaymentHelp =>
      'Pesapal needs a phone number or an email for your payment.';

  @override
  String get phoneNotValid => 'Enter a phone number, such as 0772 123 456.';

  @override
  String get payWithPesapal => 'Pay with Pesapal';

  @override
  String get startingPayment => 'Starting your payment';

  @override
  String get finishPaying => 'Finish paying on Pesapal';

  @override
  String get finishPayingHelp =>
      'Pesapal\'s page has opened in a new tab or in your browser. Come back here once you\'ve paid: this page checks by itself.';

  @override
  String get openPesapalAgain => 'Open Pesapal again';

  @override
  String get checkAgain => 'Check again';

  @override
  String get checkingPayment => 'Checking your payment';

  @override
  String get paymentFailedTitle => 'That payment didn\'t go through';

  @override
  String get paymentFailedHelp =>
      'You can try another way to pay on Pesapal\'s page, or choose a pass again.';

  @override
  String get paymentGivenUp =>
      'This payment wasn\'t completed. Choose a pass to try again.';

  @override
  String get stillWaitingTitle => 'Still waiting for Pesapal';

  @override
  String get stillWaitingHelp =>
      'We haven\'t heard from Pesapal yet. If you paid, your pass shows on the Account tab once it has been checked.';

  @override
  String get passReadyTitle => 'Your pass is ready';

  @override
  String passReadyUntil(String date) {
    return 'You can watch until $date.';
  }

  @override
  String get carryOnWatching => 'Carry on watching';

  @override
  String get passNotForSale =>
      'This pass isn\'t for sale any more. Choose another.';

  @override
  String get paymentsUnavailable =>
      'Payments aren\'t available right now. Try again in a few minutes.';

  @override
  String get passSignInNeeded => 'Sign in to buy a pass.';

  @override
  String get couldNotOpenPesapal =>
      'Couldn\'t open Pesapal\'s page. Use Open Pesapal again.';

  @override
  String get passNeededTitle => 'You need a pass to watch';

  @override
  String get passNeededMessage => 'Buy a pass to watch everything on VeloraUG.';

  @override
  String get passEndedTitle => 'Your pass has ended';

  @override
  String get passEndedMessage =>
      'Buy another pass to carry on from where you were.';

  @override
  String get passPrices => 'Pass prices';

  @override
  String get passPricesIntro =>
      'Prices are in Uganda shillings. Leave one empty to stop selling that pass.';

  @override
  String priceUgx(String pass) {
    return 'Price for $pass (UGX)';
  }

  @override
  String get priceNotValid =>
      'Enter a whole number from 500 to 10,000,000, or leave it empty.';

  @override
  String get savePrices => 'Save prices';

  @override
  String get pricesSaved => 'Prices saved.';

  @override
  String get choosePlanTitle => 'Choose your plan';

  @override
  String get choosePlanIntro =>
      'Every plan unlocks the whole VeloraUG catalogue. Pay once on Pesapal\'s secure page with MTN Mobile Money, Airtel Money or a card. Nothing renews by itself.';

  @override
  String get mostPopular => 'Most popular';

  @override
  String planDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String planDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count registered devices',
      one: '1 registered device',
    );
    return '$_temp0';
  }

  @override
  String planStreams(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count screens at a time',
      one: '1 screen at a time',
    );
    return '$_temp0';
  }

  @override
  String get planBenefitCatalogue => 'Every published movie and series';

  @override
  String get planBenefitPlatforms => 'Watch on the web and on Android';

  @override
  String get planBenefitNoRenewal => 'No automatic renewal';

  @override
  String payPlan(String price) {
    return 'Pay $price';
  }

  @override
  String planCardLabel(String plan, String price, String duration) {
    return '$plan, $price, $duration';
  }

  @override
  String get planQueuedNote =>
      'You have a plan running. A new one starts when it ends, so you keep every day you paid for.';

  @override
  String get paymentSecureNote =>
      'VeloraUG never sees your mobile money PIN or card number.';

  @override
  String get tooManyAttempts =>
      'Too many attempts. Wait a moment and try again.';

  @override
  String get myMembership => 'My membership';

  @override
  String get membershipActive => 'Active';

  @override
  String get membershipNone => 'No active plan';

  @override
  String get membershipNoneHelp =>
      'Choose a plan to start watching everything on VeloraUG.';

  @override
  String get membershipChecking => 'Payment being checked';

  @override
  String membershipStarted(String date) {
    return 'Started $date';
  }

  @override
  String membershipExpires(String date) {
    return 'Expires $date';
  }

  @override
  String timeLeftDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String timeLeftHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours left',
      one: '1 hour left',
    );
    return '$_temp0';
  }

  @override
  String timeLeftMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes left',
      one: '1 minute left',
    );
    return '$_temp0';
  }

  @override
  String membershipQueued(String plan, String date) {
    return 'Next: $plan, from $date';
  }

  @override
  String get renewPlan => 'Renew';

  @override
  String get changePlan => 'Change plan';

  @override
  String get choosePlan => 'Choose a plan';

  @override
  String get myDevices => 'My devices';

  @override
  String devicesAllowance(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Your plan allows $count registered devices.',
      one: 'Your plan allows 1 registered device.',
    );
    return '$_temp0';
  }

  @override
  String get devicesNone =>
      'No devices yet. A device registers itself the first time it plays.';

  @override
  String devicesOverLimit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Your plan now allows $count devices. Remove the ones you no longer use to keep watching.',
      one: 'Your plan now allows 1 device. Remove the ones you no longer use to keep watching.',
    );
    return '$_temp0';
  }

  @override
  String get devicesPolicy =>
      'Removing a device frees its place at once. To stop sharing, up to 3 replacement devices can be added every 30 days.';

  @override
  String get thisDevice => 'This device';

  @override
  String lastActive(String date) {
    return 'Last active $date';
  }

  @override
  String get removeDevice => 'Remove';

  @override
  String get removeDeviceTitle => 'Remove this device?';

  @override
  String removeDeviceMessage(String device) {
    return '$device stops playing within a minute. It can register again later, as a new device.';
  }

  @override
  String get deviceRemovedNotice => 'Device removed.';

  @override
  String get renameDevice => 'Rename';

  @override
  String get deviceName => 'Device name';

  @override
  String get deviceRenamed => 'Name saved.';

  @override
  String get platformWeb => 'Web browser';

  @override
  String get platformAndroid => 'Android';

  @override
  String get platformOther => 'Other device';

  @override
  String get devicesCouldNotLoad => 'Couldn\'t load your devices.';

  @override
  String get playingNow => 'Playing now';

  @override
  String playingOn(String device, String time) {
    return 'On $device since $time';
  }

  @override
  String get stopPlayback => 'Stop';

  @override
  String sessionStoppedNotice(String device) {
    return 'Playback stopped on $device.';
  }

  @override
  String get paymentsHeading => 'Payments';

  @override
  String get paymentsNone => 'No payments yet.';

  @override
  String get paymentsCouldNotLoad => 'Couldn\'t load your payments.';

  @override
  String get paymentStateCompleted => 'Paid';

  @override
  String get paymentStatePending => 'Being checked';

  @override
  String get paymentStateFailed => 'Failed';

  @override
  String get paymentStateReversed => 'Reversed';

  @override
  String get paymentStateAbandoned => 'Not completed';

  @override
  String paymentReference(String reference) {
    return 'Ref. $reference';
  }

  @override
  String get deviceLimitTitle => 'Device limit reached';

  @override
  String get deviceLimitMessage =>
      'Every device your plan allows is registered. Remove one you no longer use, then try again.';

  @override
  String get manageDevices => 'Manage devices';

  @override
  String get streamLimitTitle => 'Playing on another device';

  @override
  String get streamLimitMessage =>
      'Every screen your plan allows is in use. Stop playback on another device to watch here.';

  @override
  String stopOnDeviceAndWatch(String device) {
    return 'Stop on $device and watch here';
  }

  @override
  String get deviceSwitchLimitMessage =>
      'This account has added too many new devices in the last 30 days. Keep watching on a registered device, or contact VeloraUG support.';

  @override
  String get sessionEndedTitle => 'Playback stopped';

  @override
  String get sessionEndedMessage =>
      'Playback was stopped from another device, or this device was removed.';

  @override
  String get watchHereAgain => 'Watch here again';

  @override
  String get adminSubscriptions => 'Subscriptions';

  @override
  String get adminOverview => 'Overview';

  @override
  String get metricActiveSubscribers => 'Active subscribers';

  @override
  String get metricRevenue => 'Revenue, last 30 days';

  @override
  String get metricFailed => 'Failed, last 30 days';

  @override
  String get metricReversed => 'Reversed, last 30 days';

  @override
  String get metricPending => 'Being checked now';

  @override
  String get metricDevices => 'Registered devices';

  @override
  String get metricPlaying => 'Playing now';

  @override
  String get adminPlans => 'Plans';

  @override
  String get adminPlansIntro =>
      'Prices are in whole Uganda shillings. A change applies to new payments only: what was already bought keeps its price, length and devices. Every change is recorded.';

  @override
  String get planOnSale => 'On sale';

  @override
  String get planFeatured => 'Featured';

  @override
  String get planLegacy => 'Legacy pass, kept for history';

  @override
  String planSummary(String duration, String devices) {
    return '$duration · $devices';
  }

  @override
  String get savePlan => 'Save';

  @override
  String planSaved(String plan) {
    return '$plan saved.';
  }

  @override
  String get adminPayments => 'Payments';

  @override
  String get paymentsFilterAll => 'All';

  @override
  String get adminSubscribers => 'Active subscribers';

  @override
  String get subscribersNone => 'No one has an active plan.';

  @override
  String subscriberLine(String plan, String date, String devices) {
    return '$plan until $date · $devices';
  }

  @override
  String get adminDevicesOf => 'Devices';

  @override
  String adminRemoveDeviceMessage(String device) {
    return '$device stops playing within a minute. The account holder can register it again.';
  }

  @override
  String get priceHistory => 'Price history';

  @override
  String priceChange(String plan, String from, String to) {
    return '$plan: $from to $to';
  }

  @override
  String get noPrice => 'no price';
}
