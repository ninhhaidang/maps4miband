#!/usr/bin/env python3
"""Hà Nội's streets for the grey streets on the band, bundled in the app as ios/Maps4MiBand/hanoi-streets.bin.

From an OpenStreetMap extract (https://download.geofabrik.de/asia/vietnam-latest.osm.pbf) through QGIS's ogr2ogr:

    ogr2ogr -f GeoJSONSeq hanoi.geojsonl vietnam-latest.osm.pbf lines \\
        -spat 105.70 20.90 105.95 21.13 -where "highway IS NOT NULL" -select highway
    python3 tools/streets.py hanoi.geojsonl ios/Maps4MiBand/hanoi-streets.bin

Output (StreetMap in ios/Navigator): raw deflate of little-endian int32s, per street its point count, then lat and
lon x 1e5 per point.
"""
import array
import json
import sys
import zlib

# Lanes are mostly `service` in Hà Nội, so they stay; ways a motorbike can't take go, expressways too.
NOT_FOR_MOTORBIKES = {"footway", "steps", "cycleway", "path", "pedestrian", "bridleway", "corridor", "platform",
                      "proposed", "construction", "motorway", "motorway_link"}


def main(src, dst):
    ints = array.array("i")
    streets = points = 0
    with open(src) as f:
        for line in f:
            feature = json.loads(line)
            geometry = feature.get("geometry") or {}
            if feature["properties"].get("highway") in NOT_FOR_MOTORBIKES or geometry.get("type") != "LineString":
                continue
            coords = geometry["coordinates"]
            ints.append(len(coords))
            for lon, lat in coords:
                ints.extend((round(lat * 1e5), round(lon * 1e5)))
            streets += 1
            points += len(coords)
    if sys.byteorder != "little":
        ints.byteswap()
    deflate = zlib.compressobj(9, zlib.DEFLATED, -15)
    data = deflate.compress(ints.tobytes()) + deflate.flush()
    with open(dst, "wb") as f:
        f.write(data)
    print(f"{streets} streets, {points} points, {len(data) / 1e6:.1f} MB")


if __name__ == "__main__":
    main(*sys.argv[1:])
