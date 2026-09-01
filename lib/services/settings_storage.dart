// Selects the mobile/desktop or browser implementation of local settings.
//
// Android and iOS use SQLite as required by the revised FYP. The browser uses
// its normal key-value plugin because browser builds cannot open sqflite files.

export 'settings_storage_web.dart'
    if (dart.library.io) 'settings_storage_io.dart';
