// Versjon og bygg. GitHub Actions setter dem med --dart-define; tomme når du bygger selv.

const String appVersion = String.fromEnvironment('FYRLYS_VERSION');
const String appBuild = String.fromEnvironment('FYRLYS_BUILD');
const String appCommit = String.fromEnvironment('FYRLYS_COMMIT');

/// «Fyrlys 0.1.0 · bygg 12 (a1b2c3d)», så det er lett å se hvilket testbygg som kjører.
String get appBuildLabel {
  final version = appVersion.isEmpty ? '' : ' $appVersion';
  if (appBuild.isEmpty) return 'Fyrlys$version (eget bygg)';
  final commit = appCommit.isEmpty ? '' : ' ($appCommit)';
  return 'Fyrlys$version · bygg $appBuild$commit';
}
