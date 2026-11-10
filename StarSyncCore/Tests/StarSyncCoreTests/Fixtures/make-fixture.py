#!/usr/bin/env python3
"""Builds tiny.mcat, a synthetic stand-in for a Lightroom CC catalog.

The real catalog is 430 MB of personal photos, so it cannot be committed or
used in CI. This writes a small SQLite file with the same `docs`/`revs` schema
and MessagePack-encoded records, covering every rating, the record shapes the
reader has to skip, and a spread of MessagePack type widths.

Standard library only. Run from this directory:

    python3 make-fixture.py
"""

import hashlib
import os
import sqlite3
import struct

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tiny.mcat")


# --- MessagePack encoder (only what the fixture needs) ---------------------

def enc(o, *, force=None):
    if force == "str16":
        b = o.encode(); return b"\xda" + struct.pack(">H", len(b)) + b
    if force == "str8":
        b = o.encode(); return b"\xd9" + bytes([len(b)]) + b
    if force == "uint16":
        return b"\xcd" + struct.pack(">H", o)
    if force == "uint32":
        return b"\xce" + struct.pack(">I", o)
    if force == "int8":
        return b"\xd0" + struct.pack(">b", o)
    if force == "float64":
        return b"\xcb" + struct.pack(">d", o)
    if force == "map16":
        items = b"".join(enc(k) + enc(v) for k, v in o.items())
        return b"\xde" + struct.pack(">H", len(o)) + items

    if o is None:
        return b"\xc0"
    if o is True:
        return b"\xc3"
    if o is False:
        return b"\xc2"
    if isinstance(o, bytes):
        return b"\xc4" + bytes([len(o)]) + o
    if isinstance(o, int):
        if 0 <= o <= 0x7f:
            return bytes([o])
        if -32 <= o < 0:
            return bytes([o + 256])
        if 0 <= o <= 0xff:
            return b"\xcc" + bytes([o])
        if 0 <= o <= 0xffff:
            return b"\xcd" + struct.pack(">H", o)
        return b"\xce" + struct.pack(">I", o)
    if isinstance(o, float):
        return b"\xcb" + struct.pack(">d", o)
    if isinstance(o, str):
        b = o.encode()
        if len(b) <= 31:
            return bytes([0xa0 | len(b)]) + b
        if len(b) <= 0xff:
            return b"\xd9" + bytes([len(b)]) + b
        return b"\xda" + struct.pack(">H", len(b)) + b
    if isinstance(o, list):
        items = b"".join(enc(v) for v in o)
        if len(o) <= 15:
            return bytes([0x90 | len(o)]) + items
        return b"\xdc" + struct.pack(">H", len(o)) + items
    if isinstance(o, dict):
        items = b"".join(enc(k) + enc(v) for k, v in o.items())
        if len(o) <= 15:
            return bytes([0x80 | len(o)]) + items
        return b"\xde" + struct.pack(">H", len(o)) + items
    raise TypeError(repr(o))


# --- Fixture content ------------------------------------------------------

USER = "fixtureuser0000000000000000000000"
# Stands in for the kilobytes of Camera Raw XMP the reader skips.
BIG_XMP = "<x:xmpmeta>" + ("<crs:Exposure2012>+0.62</crs:Exposure2012>" * 40) + "</x:xmpmeta>"

docs = []  # (fullDocId, deleted, type, subtype, record)


def asset(doc_id, filename, rating, *, capture="2026-01-02T03:04:05",
          flag=None, deleted=0, subtype="image", width=6240, height=4160,
          include_ratings=True, extras=None):
    record = {
        "type": "asset",
        "subtype": subtype,
        "captureDate": capture,
        "importSource": {
            "fileName": filename,
            "sha256": hashlib.sha256(doc_id.encode()).hexdigest(),
            "originalWidth": width,
            "originalHeight": height,
            "fileSize": 23791280,
        },
        # Always present, always skipped by the reader.
        "develop": {"xmpCameraRaw": BIG_XMP, "croppedWidth": width},
    }
    if include_ratings:
        record["ratings"] = {USER: {"rating": rating, "date": "2026-01-03T00:00:00Z"}}
    if flag:
        record["reviews"] = {USER: {"flag": flag, "date": "2026-01-03T00:00:00Z"}}
    if extras:
        record.update(extras)
    docs.append((doc_id, deleted, "asset", subtype, record))


# One photo at each rating 0-5.
asset("a000", "DSC_0000.NEF", 0)
asset("a001", "DSC_0001.NEF", 1)
asset("a002", "DSC_0002.NEF", 2)
asset("a003", "DSC_0003.NEF", 3)
asset("a004", "DSC_0004.NEF", 4)
asset("a005", "DSC_0005.NEF", 5)

# No `ratings` key at all — 550 real photos look like this. Must read as 0.
asset("a006", "DSC_0006.NEF", 0, include_ratings=False)

# Pick and reject flags, read for display only.
asset("a007", "DSC_0007.NEF", 5, flag="pick")
asset("a008", "DSC_0008.NEF", 1, flag="reject")

# Two photos sharing a stem, separable only by capture time.
asset("a009", "DSCF4087.RAF", 4, capture="2026-02-01T10:00:00")
asset("a010", "DSCF4087.RAF", 2, capture="2026-02-01T18:30:00")

# A derived file, as Lightroom names edited exports.
asset("a011", "DSCF3438-Edit.tiff", 5)

# Unusual but valid MessagePack widths, to exercise the decoder.
asset("a012", "DSC_0012.NEF", 3, extras={
    "wideCount": 70000,          # uint32
    "mediumCount": 400,          # uint16
    "negative": -7,              # negative fixint
    "ratio": 1.5,                # float64
    "flagged": True,
    "nothing": None,
    "tags": ["one", "two", "three"],
    "thumbnail": b"\x00\x01\x02\x03",
    "longNote": "n" * 300,       # str16
})

# A 16-key map forces map16 rather than fixmap.
asset("a013", "DSC_0013.NEF", 2, extras={f"pad{i}": i for i in range(10)})

# Rows the reader must leave out.
asset("a900", "DSC_0900.NEF", 5, deleted=1)                       # tombstoned
asset("a901", "DSC_0901.NEF", 5, subtype="deleted_image")         # deleted subtype
asset("a902", "MOVIE.MOV", 5, subtype="video")                    # not a photo
asset("a903", "FACE.jpg", 5, subtype="person")                    # face thumbnail
asset("a904", "PRESET", 5, subtype="preset")                      # not a photo

# Albums.
docs.append(("set1", 0, "album", "collection_set",
             {"type": "album", "name": "Trips", "subtype": "collection_set"}))
docs.append(("col1", 0, "album", "collection",
             {"type": "album", "name": "[26-01] Fixture Album", "subtype": "collection",
              "parent": {"id": "set1"}}))
docs.append(("col2", 0, "album", "collection",
             {"type": "album", "name": "Empty Album", "subtype": "collection"}))
docs.append(("prj1", 0, "album", "project",
             {"type": "album", "name": "Fixture Project", "subtype": "project"}))
docs.append(("col9", 0, "album", "collection",
             {"type": "album", "name": "Deleted Album", "subtype": "collection"}))
docs[-1] = ("col9", 1, "album", "collection", docs[-1][4])

# Membership: six photos in col1, two in prj1, one link from a deleted album.
members = [("col1", a) for a in ["a001", "a002", "a003", "a004", "a005", "a009"]]
members += [("prj1", a) for a in ["a007", "a008"]]
members += [("col9", "a001")]
for i, (album, asset_id) in enumerate(members):
    docs.append((f"link{i:03d}", 0, "album_asset", None,
                 {"type": "album_asset", "album": {"id": album}, "asset": {"id": asset_id}}))


# --- Write ----------------------------------------------------------------

if os.path.exists(OUT):
    os.remove(OUT)

con = sqlite3.connect(OUT)
con.executescript("""
CREATE TABLE docs(
    localDocId INTEGER PRIMARY KEY,
    fullDocId TEXT UNIQUE NOT NULL,
    winningRevSequence INTEGER,
    mostRecentRevSequence INTEGER,
    deleted BOOLEAN DEFAULT 0,
    hasConflicts BOOLEAN DEFAULT 0,
    annotation BLOB,
    spaceId TEXT,
    type TEXT,
    subtype TEXT);
CREATE TABLE revs(
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    localDocId INTEGER NOT NULL,
    revId TEXT NOT NULL,
    parentRevSequence INTEGER,
    current BOOLEAN,
    deleted BOOLEAN DEFAULT 0,
    content BLOB);
CREATE TABLE schemaVersion(version INTEGER);
INSERT INTO schemaVersion VALUES (9);
""")

for local_id, (full_id, deleted, type_, subtype, record) in enumerate(docs, start=1):
    # A superseded earlier revision, so `winningRevSequence` is doing real work.
    con.execute(
        "INSERT INTO revs(localDocId, revId, current, deleted, content) VALUES (?,?,?,?,?)",
        (local_id, f"{full_id}-old", 0, 0, enc({"type": type_, "stale": True})),
    )
    cur = con.execute(
        "INSERT INTO revs(localDocId, revId, current, deleted, content) VALUES (?,?,?,?,?)",
        (local_id, f"{full_id}-cur", 1, 0, enc(record)),
    )
    con.execute(
        "INSERT INTO docs(localDocId, fullDocId, winningRevSequence, mostRecentRevSequence,"
        " deleted, type, subtype) VALUES (?,?,?,?,?,?,?)",
        (local_id, full_id, cur.lastrowid, cur.lastrowid, deleted, type_, subtype),
    )

con.commit()
con.execute("VACUUM")
con.close()
print(f"wrote {OUT} ({os.path.getsize(OUT)} bytes, {len(docs)} docs)")
