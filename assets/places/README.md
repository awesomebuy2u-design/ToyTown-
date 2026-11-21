# Settlement centres for the ToyTown map

Source: https://download.geonames.org/export/dump/UA.zip, retrieved 2026-11-21.
Source ZIP SHA-256: `94a1dde877a4e00c358fa75def45025cda4dd121e5647bf92511369411f169f7`.

GeoNames, Creative Commons Attribution 4.0: https://creativecommons.org/licenses/by/4.0/.
Attribution is displayed below the map. Data format: https://download.geonames.org/export/dump/readme.txt.

`ukraine.json` contains 32,463 populated-place records within the UA country extract,
including Crimea. Only current populated-place feature codes are retained; quarters,
abandoned places, historical places and non-settlement features are excluded.
The records describe settlement centres, never the position of a family or device.

Each row is `[geonameId, latitude, longitude, rank, aliases]`.
Rank 0 denotes a national or regional capital; rank 1 denotes other settlements.
Aliases contain the primary name, ASCII name and Cyrillic alternatives from GeoNames.
These are lookup aliases, not the UI label; the UI uses the published listing city.

Lookup matches whole normalized names. A regional capital wins a name collision;
other ambiguous names and unknown names receive no map point and remain in the list.
No online geocoder receives listing text, search terms, family details or addresses.
The map background uses OpenStreetMap tiles and their displayed attribution.

Rebuild with `python3 tools/build_settlements.py /path/to/UA.zip`.
