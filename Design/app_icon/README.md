# Trink-Tracker App-Icon

Wasserglas mit Welle und Tropfen als Vektorgeometrie. Die SVGs hier sind
editierbare **Vorschauen**; die Quelle für den Asset-Katalog ist
`Design/generate_app_icons.swift`.

Neu erzeugen (vom Repository-Stamm, macOS mit Xcode):

```sh
swift Design/generate_app_icons.swift
```

Das Skript schreibt `TrinkTracker/Assets.xcassets/AppIcon.appiconset/` neu:
`Icon-light-1024.png`, `Icon-dark-1024.png`, `Icon-tinted-1024.png` (opak, ohne
eingebackene Eckenrundung, Tinted in Graustufen) samt `Contents.json`. iOS wählt
die Erscheinung selbst, unabhängig vom Theme innerhalb der App.

## Farben ändern

Die Paletten je Erscheinung stehen im Skript unter `palettes`
(Verlauf oben, Verlauf unten, Symbolfarbe). Aktuell Aqua-Blau; die App ist innen
in „Minze & Honig“ (Grün `#A8D5BA` / `#47825F` / `#22392C`) gehalten — ob das Icon
mitzieht, ist eine offene Designentscheidung (siehe GOTO.md).

Die Android-Exporte der Flutter-Version (adaptive Icons, Mipmaps) wurden beim
Port bewusst entfernt.
