// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show JSON;
import 'dart:io';

import 'package:path/path.dart' as path;

import 'usage_impl.dart';

/// An interface to a Google Analytics session, suitable for use in command-line
/// applications.
///
/// `trackingId`, `applicationName`, and `applicationVersion` values should be supplied.
/// `analyticsUrl` is optional, and lets user's substitute their own analytics URL for
/// the default.
///
/// `documentDirectory` is where the analytics settings are stored. It
/// defaults to the user home directory. For regular `dart:io` apps this doesn't need to
/// be supplied. For Flutter applications, you should pass in a value like
/// `PathProvider.getApplicationDocumentsDirectory()`.
class AnalyticsIO extends AnalyticsImpl {
  AnalyticsIO(
      String trackingId, String applicationName, String applicationVersion,
      {String analyticsUrl, Directory documentDirectory})
      : super(
            trackingId,
            new IOPersistentProperties(applicationName,
                documentDirPath: documentDirectory?.path),
            new IOPostHandler(),
            applicationName: applicationName,
            applicationVersion: applicationVersion,
            analyticsUrl: analyticsUrl) {
    final String locale = getPlatformLocale();
    if (locale != null) {
      setSessionValue('ul', locale);
    }
  }
}

String _createUserAgent() {
  final String locale = getPlatformLocale() ?? '';

  if (Platform.isAndroid) {
    return 'Mozilla/5.0 (Android; Mobile; ${locale})';
  } else if (Platform.isIOS) {
    return 'Mozilla/5.0 (iPhone; U; CPU iPhone OS like Mac OS X; ${locale})';
  } else if (Platform.isMacOS) {
    return 'Mozilla/5.0 (Macintosh; Intel Mac OS X; Macintosh; ${locale})';
  } else if (Platform.isWindows) {
    return 'Mozilla/5.0 (Windows; Windows; Windows; ${locale})';
  } else if (Platform.isLinux) {
    return 'Mozilla/5.0 (Linux; Linux; Linux; ${locale})';
  } else {
    // Dart/1.8.0 (macos; macos; macos; en_US)
    String os = Platform.operatingSystem;
    return "Dart/${getDartVersion()} (${os}; ${os}; ${os}; ${locale})";
  }
}

String _userHomeDir() {
  String envKey = Platform.operatingSystem == 'windows' ? 'APPDATA' : 'HOME';
  String value = Platform.environment[envKey];
  return value == null ? '.' : value;
}

String getDartVersion() {
  String ver = Platform.version;
  int index = ver.indexOf(' ');
  if (index != -1) ver = ver.substring(0, index);
  return ver;
}

class IOPostHandler extends PostHandler {
  final String _userAgent;
  final HttpClient mockClient;

  IOPostHandler({HttpClient this.mockClient}) : _userAgent = _createUserAgent();

  Future sendPost(String url, Map<String, dynamic> parameters) async {
    String data = postEncode(parameters);

    HttpClient client = mockClient != null ? mockClient : new HttpClient();
    client.userAgent = _userAgent;
    try {
      HttpClientRequest req = await client.postUrl(Uri.parse(url));
      req.write(data);
      HttpClientResponse response = await req.close();
      response.drain();
    } catch (exception) {
      // Catch errors that can happen during a request, but that we can't do
      // anything about, e.g. a missing internet connection.
    }
  }
}

class IOPersistentProperties extends PersistentProperties {
  File _file;
  Map _map;

  IOPersistentProperties(String name, {String documentDirPath}) : super(name) {
    String fileName = '.${name.replaceAll(' ', '_')}';
    documentDirPath ??= _userHomeDir();
    _file = new File(path.join(documentDirPath, fileName));

    try {
      if (!_file.existsSync()) _file.createSync();
      String contents = _file.readAsStringSync();
      if (contents.isEmpty) contents = '{}';
      _map = JSON.decode(contents);
    } catch (_) {
      _map = {};
    }
  }

  dynamic operator [](String key) => _map[key];

  void operator []=(String key, dynamic value) {
    if (value == null && !_map.containsKey(key)) return;
    if (_map[key] == value) return;

    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }

    try {
      _file.writeAsStringSync(JSON.encode(_map) + '\n');
    } catch (_) {}
  }
}

/// Return the string for the platform's locale; return's `null` if the locale
/// can't be determined.
String getPlatformLocale() {
  String locale = Platform.environment['LANG'];
  if (locale == null) return null;

  if (locale != null) {
    // Convert `en_US.UTF-8` to `en_US`.
    int index = locale.indexOf('.');
    if (index != -1) locale = locale.substring(0, index);

    // Convert `en_US` to `en-us`.
    locale = locale.replaceAll('_', '-').toLowerCase();
  }

  return locale;
}
