import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Which version of the app this is, as the build says (`pubspec.yaml`).
class AppInfo {
  const AppInfo({required this.version, required this.build});

  final String version;
  final String build;

  /// "1.0.0 (1)"; the build is left out when the platform does not give one.
  String get label => build.isEmpty ? version : '$version ($build)';
}

/// Read once from the installed app. Tests replace it with a fixed value.
final appInfoProvider = FutureProvider<AppInfo>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppInfo(version: info.version, build: info.buildNumber);
});
