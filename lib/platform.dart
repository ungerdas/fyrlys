import 'dart:io';

/// Fyrlys på en Android-telefon (ellers på en Windows-PC). Testene kan sette den for å prøve telefon-greinene.
bool isAndroid = Platform.isAndroid;

/// Fyrlys på en Samsung-TV (Tizen). Settes i bygget for TV-en (`--dart-define=FYRLYS_TIZEN=true`), fordi Tizen ser
/// ut som Linux for Dart; testene kan sette den for å prøve TV-greinene.
bool isTizen = const bool.fromEnvironment('FYRLYS_TIZEN') || Platform.environment.containsKey('TIZEN_API_VERSION');

/// Fyrlys på en PC (Windows): vinduer, mus, minispiller, volumknapp, Chromecast og oppdatering som legges inn selv.
bool get isPc => !isAndroid && !isTizen;

/// Casting til en Chromecast (fra PC-en og telefonen; ikke fra TV-en, som selv er TV-en).
bool get canCast => !isTizen;

/// Spilleren fyller alltid skjermen (telefonen og TV-en): ingen fullskjerm-knapp i filmspilleren.
bool get alwaysFull => isAndroid || isTizen;

/// Telefonen og TV-en: spilleren gir fra seg strømmen når appen legges bort, og åpner den igjen når du kommer
/// tilbake (på PC-en spiller den videre).
bool get pausesInBackground => isAndroid || isTizen;
