// Versjon og bygg. GitHub Actions setter dem med --dart-define; tomme når du bygger selv.

const String appVersion = String.fromEnvironment('FYRLYS_VERSION');
const String appBuild = String.fromEnvironment('FYRLYS_BUILD');
const String appCommit = String.fromEnvironment('FYRLYS_COMMIT');

/// repoet med testbyggene appen oppdaterer seg fra (et fork bygger med sitt eget)
const String appRepo = String.fromEnvironment('FYRLYS_REPO', defaultValue: 'ungerdas/fyrlys');

/// «Fyrlys 2.0.2 (a1b2c3d)»: versjonen og commiten. Byggnummeret brukes bare av oppdateringen.
String get appBuildLabel {
  final version = appVersion.isEmpty ? '' : ' $appVersion';
  if (appBuild.isEmpty) return 'Fyrlys$version (eget bygg)';
  final commit = appCommit.isEmpty ? '' : ' ($appCommit)';
  return 'Fyrlys$version$commit';
}
