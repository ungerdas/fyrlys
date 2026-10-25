import 'dart:io';

/// PC (Windows, macOS, Linux): eget vindu, fullskjerm via window_manager.
final bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
