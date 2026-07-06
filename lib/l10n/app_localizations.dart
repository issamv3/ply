import 'package:flutter/material.dart';

class AppLocalizations {
  AppLocalizations(this.locale);
  final Locale locale;

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static const delegate = _AppLocalizationsDelegate();

  static const supportedLocales = [Locale('en'), Locale('ar')];

  bool get isArabic => locale.languageCode == 'ar';

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'appName': 'Ply',
      'splashSubtitle': 'Your smart media player',
      'enterSource': 'Enter stream URL or paste MPD XML',
      'urlHint': 'https://example.com/stream.mpd',
      'xmlHint': 'Paste MPD XML content here…',
      'play': 'Play',
      'settings': 'Settings',
      'theme': 'Theme',
      'themeLight': 'Light',
      'themeDark': 'Dark',
      'themeSystem': 'Follow System',
      'language': 'Language',
      'langArabic': 'Arabic',
      'langEnglish': 'English',
      'langSystem': 'Follow System',
      'quality': 'Quality',
      'auto': 'Auto (Adaptive)',
      'speed': 'Speed',
      'volume': 'Volume',
      'brightness': 'Brightness',
      'lock': 'Lock',
      'unlock': 'Unlock',
      'forward10': '+10s',
      'backward10': '-10s',
      'loading': 'Loading…',
      'error': 'Error loading video',
      'selectQuality': 'Select Quality',
      'selectSpeed': 'Playback Speed',
      'appearance': 'Appearance',
      'about': 'About',
      'version': 'Version',
      'screenLocked': 'Screen Locked',
      'doubleTapUnlock': 'Double-tap to unlock',
      'network': 'Network',
      'fbCdn': 'Facebook Free CDN',
      'fbCdnDesc': 'Rewrite fbcdn.net links to free CDN endpoint',
      'aspectRatio': 'Aspect Ratio',
      'aspectContain': 'Fit (Default)',
      'aspectCover': 'Fill Screen',
      'aspectStretch': 'Stretch',
      'aspect43': '4:3',
      'aspect169': '16:9',
      'loop': 'Loop',
      'loopOn': 'Loop On',
      'loopOff': 'Loop Off',
      'sleepTimer': 'Sleep Timer',
      'sleepTimerOff': 'Off',
      'sleepTimerSet': 'Timer set for',
      'sleepTimerRemaining': 'remaining',
      'sleepTimerCancel': 'Cancel Timer',
      'rotate': 'Rotate',
      'fitMode': 'Fit Mode',
      'autoRotate': 'Auto-Rotate',
      'autoRotateDesc': 'Follow device orientation automatically',
      'download': 'Download',
      'downloadTitlePrompt': 'Enter video title',
      'downloadTitleHint': 'My video',
      'downloadCancel': 'Cancel',
      'downloadStart': 'Download',
      'downloading': 'Downloading…',
      'downloadMerging': 'Merging audio and video…',
      'downloadStarted': 'Download started — check notifications for progress',
      'downloadSuccess': 'Saved to gallery',
      'downloadFailed': 'Download failed',
      'continueWatching': 'Continue Watching',
      'noHistory': 'No videos watched yet',
      'noHistorySubtitle': 'Videos you play will show up here',
      'clearHistory': 'Clear history',
      'resume': 'Resume',
      'addNewVideo': 'Add Video',
      'rename': 'Rename',
      'renameVideo': 'Rename video',
      'renameHint': 'New name',
      'delete': 'Delete',
      'deleteFromHistory': 'Remove from history',
      'justNow': 'Just now',
      'minutesAgo': 'm ago',
      'hoursAgo': 'h ago',
      'daysAgo': 'd ago',
      'watched': 'watched',
      'downloads': 'Downloads',
      'noDownloads': 'No downloads yet',
      'noDownloadsSubtitle': 'Videos you download will show up here',
      'deleteDownload': 'Delete download',
      'deleteDownloadConfirm': 'Delete this video from your device?',
      'nowDownloading': 'Downloading',
      'downloadedVideos': 'Downloaded',
      'cancelDownload': 'Cancel',
      'cancelDownloadConfirm': 'Cancel this download?',
      'showLess': 'Show less',
      'searchHint': 'Search history and downloads...',
      'searchEmpty': 'Type to search',
      'searchNoResults': 'No results',
    },
    'ar': {
      'appName': 'بلاي',
      'splashSubtitle': 'مشغل الوسائط الذكي',
      'enterSource': 'أدخل رابط البث أو الصق كود MPD',
      'urlHint': 'https://example.com/stream.mpd',
      'xmlHint': 'الصق محتوى MPD XML هنا…',
      'play': 'تشغيل',
      'settings': 'الإعدادات',
      'theme': 'المظهر',
      'themeLight': 'فاتح',
      'themeDark': 'داكن',
      'themeSystem': 'تبعاً للنظام',
      'language': 'اللغة',
      'langArabic': 'العربية',
      'langEnglish': 'الإنجليزية',
      'langSystem': 'تبعاً للنظام',
      'quality': 'الجودة',
      'auto': 'تلقائي (تكيّفي)',
      'speed': 'السرعة',
      'volume': 'الصوت',
      'brightness': 'السطوع',
      'lock': 'قفل',
      'unlock': 'فتح القفل',
      'forward10': '+١٠ ث',
      'backward10': '-١٠ ث',
      'loading': 'جارٍ التحميل…',
      'error': 'خطأ في تحميل الفيديو',
      'selectQuality': 'اختر الجودة',
      'selectSpeed': 'سرعة التشغيل',
      'appearance': 'المظهر',
      'about': 'حول التطبيق',
      'version': 'الإصدار',
      'screenLocked': 'الشاشة مقفلة',
      'doubleTapUnlock': 'انقر مرتين للفتح',
      'network': 'الشبكة',
      'fbCdn': 'CDN فيسبوك المجاني',
      'fbCdnDesc': 'تحويل روابط fbcdn.net إلى خادم CDN المجاني',
      'aspectRatio': 'نسبة العرض',
      'aspectContain': 'ملاءمة (افتراضي)',
      'aspectCover': 'ملء الشاشة',
      'aspectStretch': 'تمدد',
      'aspect43': '٤:٣',
      'aspect169': '١٦:٩',
      'loop': 'تكرار',
      'loopOn': 'التكرار مفعّل',
      'loopOff': 'التكرار معطّل',
      'sleepTimer': 'مؤقت النوم',
      'sleepTimerOff': 'إيقاف',
      'sleepTimerSet': 'سيتوقف بعد',
      'sleepTimerRemaining': 'متبقٍ',
      'sleepTimerCancel': 'إلغاء المؤقت',
      'rotate': 'تدوير',
      'fitMode': 'وضع العرض',
      'autoRotate': 'تدوير تلقائي',
      'autoRotateDesc': 'اتباع اتجاه الجهاز تلقائياً',
      'download': 'تحميل',
      'downloadTitlePrompt': 'أدخل عنوان الفيديو',
      'downloadTitleHint': 'فيديو',
      'downloadCancel': 'إلغاء',
      'downloadStart': 'تحميل',
      'downloading': 'جارٍ التحميل…',
      'downloadMerging': 'جارٍ دمج الصوت والفيديو…',
      'downloadStarted': 'بدأ التحميل — تابع التقدم في الإشعارات',
      'downloadSuccess': 'تم الحفظ في المعرض',
      'downloadFailed': 'فشل التحميل',
      'continueWatching': 'متابعة المشاهدة',
      'noHistory': 'لم تشاهد أي فيديو بعد',
      'noHistorySubtitle': 'ستظهر هنا الفيديوهات التي تشغّلها',
      'clearHistory': 'مسح السجل',
      'resume': 'استكمال',
      'addNewVideo': 'إضافة فيديو',
      'rename': 'تغيير الاسم',
      'renameVideo': 'تغيير اسم الفيديو',
      'renameHint': 'اسم جديد',
      'delete': 'حذف',
      'deleteFromHistory': 'إزالة من السجل',
      'justNow': 'الآن',
      'minutesAgo': 'د',
      'hoursAgo': 'س',
      'daysAgo': 'ي',
      'watched': 'تمت مشاهدته',
      'downloads': 'التنزيلات',
      'noDownloads': 'لا توجد تنزيلات بعد',
      'noDownloadsSubtitle': 'ستظهر هنا الفيديوهات التي تقوم بتنزيلها',
      'deleteDownload': 'حذف التنزيل',
      'deleteDownloadConfirm': 'هل تريد حذف هذا الفيديو من جهازك؟',
      'nowDownloading': 'جاري التحميل',
      'downloadedVideos': 'تم التحميل',
      'cancelDownload': 'إلغاء',
      'cancelDownloadConfirm': 'هل تريد إلغاء التحميل؟',
      'showLess': 'عرض أقل',
      'searchHint': 'بحث في السجل والتحميلات...',
      'searchEmpty': 'اكتب للبحث',
      'searchNoResults': 'لا توجد نتائج',
    },
  };

  String get(String key) =>
      _strings[locale.languageCode]?[key] ?? _strings['en']![key] ?? key;

  String get appName => get('appName');
  String get splashSubtitle => get('splashSubtitle');
  String get enterSource => get('enterSource');
  String get urlHint => get('urlHint');
  String get xmlHint => get('xmlHint');
  String get play => get('play');
  String get settings => get('settings');
  String get theme => get('theme');
  String get themeLight => get('themeLight');
  String get themeDark => get('themeDark');
  String get themeSystem => get('themeSystem');
  String get language => get('language');
  String get langArabic => get('langArabic');
  String get langEnglish => get('langEnglish');
  String get langSystem => get('langSystem');
  String get quality => get('quality');
  String get auto => get('auto');
  String get speed => get('speed');
  String get volume => get('volume');
  String get brightness => get('brightness');
  String get lock => get('lock');
  String get unlock => get('unlock');
  String get forward10 => get('forward10');
  String get backward10 => get('backward10');
  String get loading => get('loading');
  String get error => get('error');
  String get selectQuality => get('selectQuality');
  String get selectSpeed => get('selectSpeed');
  String get appearance => get('appearance');
  String get about => get('about');
  String get version => get('version');
  String get screenLocked => get('screenLocked');
  String get doubleTapUnlock => get('doubleTapUnlock');
  String get network => get('network');
  String get fbCdn => get('fbCdn');
  String get fbCdnDesc => get('fbCdnDesc');
  String get aspectRatio => get('aspectRatio');
  String get aspectContain => get('aspectContain');
  String get aspectCover => get('aspectCover');
  String get aspectStretch => get('aspectStretch');
  String get aspect43 => get('aspect43');
  String get aspect169 => get('aspect169');
  String get loop => get('loop');
  String get loopOn => get('loopOn');
  String get loopOff => get('loopOff');
  String get sleepTimer => get('sleepTimer');
  String get sleepTimerOff => get('sleepTimerOff');
  String get sleepTimerSet => get('sleepTimerSet');
  String get sleepTimerRemaining => get('sleepTimerRemaining');
  String get sleepTimerCancel => get('sleepTimerCancel');
  String get rotate => get('rotate');
  String get fitMode => get('fitMode');
  String get autoRotate => get('autoRotate');
  String get autoRotateDesc => get('autoRotateDesc');
  String get download => get('download');
  String get downloadTitlePrompt => get('downloadTitlePrompt');
  String get downloadTitleHint => get('downloadTitleHint');
  String get downloadCancel => get('downloadCancel');
  String get downloadStart => get('downloadStart');
  String get downloadStarted => get('downloadStarted');
  String get downloading => get('downloading');
  String get downloadMerging => get('downloadMerging');
  String get downloadSuccess => get('downloadSuccess');
  String get downloadFailed => get('downloadFailed');
  String get continueWatching => get('continueWatching');
  String get noHistory => get('noHistory');
  String get noHistorySubtitle => get('noHistorySubtitle');
  String get clearHistory => get('clearHistory');
  String get resume => get('resume');
  String get addNewVideo => get('addNewVideo');
  String get rename => get('rename');
  String get renameVideo => get('renameVideo');
  String get renameHint => get('renameHint');
  String get delete => get('delete');
  String get deleteFromHistory => get('deleteFromHistory');
  String get justNow => get('justNow');
  String get minutesAgo => get('minutesAgo');
  String get hoursAgo => get('hoursAgo');
  String get daysAgo => get('daysAgo');
  String get watched => get('watched');
  String get downloads => get('downloads');
  String get noDownloads => get('noDownloads');
  String get noDownloadsSubtitle => get('noDownloadsSubtitle');
  String get deleteDownload => get('deleteDownload');
  String get deleteDownloadConfirm => get('deleteDownloadConfirm');
  String get nowDownloading => get('nowDownloading');
  String get downloadedVideos => get('downloadedVideos');
  String get cancelDownload => get('cancelDownload');
  String get cancelDownloadConfirm => get('cancelDownloadConfirm');
  String get showLess => get('showLess');
  String get searchHint => get('searchHint');
  String get searchEmpty => get('searchEmpty');
  String get searchNoResults => get('searchNoResults');
  String showMore(int n) =>
      isArabic ? 'عرض $n المزيد' : 'Show $n more';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'ar'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
