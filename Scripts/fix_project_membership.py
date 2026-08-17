from pathlib import Path

project = Path("boringNotch.xcodeproj/project.pbxproj")
original = project.read_text()
planned = original


def require(text: str, anchor: str, label: str) -> None:
    if anchor not in text:
        raise SystemExit(f"{label} not found")


files = [
    ("A70000012F30000100000001", "A70100012F30000100000001", "ThermalDetailMonitor.swift"),
    ("A70000022F30000100000001", "A70100022F30000100000001", "ANCWireMapping.swift"),
    ("A70000032F30000100000001", "A70100032F30000100000001", "BudsAppModel.swift"),
    ("A70000042F30000100000001", "A70100042F30000100000001", "BudsClassicBluetoothMonitor.swift"),
    ("A70000052F30000100000001", "A70100052F30000100000001", "BudsClient.swift"),
    ("A70000062F30000100000001", "A70100062F30000100000001", "BudsModels.swift"),
    ("A70000072F30000100000001", "A70100072F30000100000001", "BudsUtils.swift"),
    ("A70000082F30000100000001", "A70100082F30000100000001", "OPOProtocol.swift"),
    ("A70000092F30000100000001", "A70100092F30000100000001", "BudsNotchView.swift"),
    ("A700000A2F30000100000001", "A701000A2F30000100000001", "LyricRomanizationService.swift"),
]

if "A70000012F30000100000001" not in planned:
    anchors = {
        "PBXBuildFile section": "/* End PBXBuildFile section */",
        "PBXFileReference section": "/* End PBXFileReference section */",
        "PBXGroup section": "/* End PBXGroup section */",
        "manager group": "\t\t\t\tED0000182F10000100000001 /* SystemStatsMonitor.swift */,\n",
        "components group": "\t\t\t\tED00001A2F10000100000001 /* System */,\n",
        "root managers group": "\t\t\t\t147163B52C5D804B0068B555 /* managers */,\n",
        "boringNotch Sources phase": "\t\t\t\t1471639A2C5D35FF0068B555 /* MusicManager.swift in Sources */,\n",
    }
    for label, anchor in anchors.items():
        require(planned, anchor, label)

    build_entries = "".join(
        f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n"
        for ref, build, name in files
    )
    ref_entries = "".join(
        f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n"
        for ref, _, name in files
    )
    groups = """\t\tA70200012F30000100000001 /* Buds */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tA70000022F30000100000001 /* ANCWireMapping.swift */,
\t\t\t\tA70000032F30000100000001 /* BudsAppModel.swift */,
\t\t\t\tA70000042F30000100000001 /* BudsClassicBluetoothMonitor.swift */,
\t\t\t\tA70000052F30000100000001 /* BudsClient.swift */,
\t\t\t\tA70000062F30000100000001 /* BudsModels.swift */,
\t\t\t\tA70000072F30000100000001 /* BudsUtils.swift */,
\t\t\t\tA70000082F30000100000001 /* OPOProtocol.swift */,
\t\t\t);
\t\t\tpath = Buds;
\t\t\tsourceTree = \"<group>\";
\t\t};
\t\tA70200022F30000100000001 /* Buds */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tA70000092F30000100000001 /* BudsNotchView.swift */,
\t\t\t);
\t\t\tpath = Buds;
\t\t\tsourceTree = \"<group>\";
\t\t};
\t\tA70200032F30000100000001 /* services */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tA700000A2F30000100000001 /* LyricRomanizationService.swift */,
\t\t\t);
\t\t\tpath = services;
\t\t\tsourceTree = \"<group>\";
\t\t};
"""
    source_entries = "".join(
        f"\t\t\t\t{build} /* {name} in Sources */,\n" for _, build, name in files
    )

    planned = planned.replace(anchors["PBXBuildFile section"], build_entries + anchors["PBXBuildFile section"], 1)
    planned = planned.replace(anchors["PBXFileReference section"], ref_entries + anchors["PBXFileReference section"], 1)
    planned = planned.replace(anchors["PBXGroup section"], groups + anchors["PBXGroup section"], 1)
    planned = planned.replace(
        anchors["manager group"],
        anchors["manager group"]
        + "\t\t\t\tA70000012F30000100000001 /* ThermalDetailMonitor.swift */,\n"
        + "\t\t\t\tA70200012F30000100000001 /* Buds */,\n",
        1,
    )
    planned = planned.replace(
        anchors["components group"],
        anchors["components group"] + "\t\t\t\tA70200022F30000100000001 /* Buds */,\n",
        1,
    )
    planned = planned.replace(
        anchors["root managers group"],
        anchors["root managers group"] + "\t\t\t\tA70200032F30000100000001 /* services */,\n",
        1,
    )
    planned = planned.replace(
        anchors["boringNotch Sources phase"],
        source_entries + anchors["boringNotch Sources phase"],
        1,
    )

lyrics_ref = "ED1000192F20000100000001"
lyrics_build = "ED1000092F20000100000001"
lyrics_group = "ED1000232F20000100000001"
lyrics_name = "LockScreenLyricLineView.swift"

if f"{lyrics_build} /* {lyrics_name} in Sources */" not in planned:
    anchor = "\t\tED1000082F20000100000001 /* LyricFeverLyricsService.swift in Sources */ = {isa = PBXBuildFile; fileRef = ED1000182F20000100000001 /* LyricFeverLyricsService.swift */; };\n"
    require(planned, anchor, "lock-screen lyric build-file anchor")
    planned = planned.replace(
        anchor,
        anchor + f"\t\t{lyrics_build} /* {lyrics_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {lyrics_ref} /* {lyrics_name} */; }};\n",
        1,
    )

if f"{lyrics_ref} /* {lyrics_name} */ = {{isa = PBXFileReference;" not in planned:
    anchor = "\t\tED1000182F20000100000001 /* LyricFeverLyricsService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LyricFeverLyricsService.swift; sourceTree = \"<group>\"; };\n"
    require(planned, anchor, "lock-screen lyric file-reference anchor")
    planned = planned.replace(
        anchor,
        anchor + f"\t\t{lyrics_ref} /* {lyrics_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {lyrics_name}; sourceTree = \"<group>\"; }};\n",
        1,
    )

if f"{lyrics_group} /* Lyrics */" not in planned:
    group_anchor = "\t\tED1000202F20000100000001 /* LockScreen */ = {\n"
    child_anchor = "\t\t\t\tED1000202F20000100000001 /* LockScreen */,\n"
    require(planned, group_anchor, "Components Lyrics group anchor")
    require(planned, child_anchor, "Components child anchor for Lyrics")
    group_entry = (
        f"\t\t{lyrics_group} /* Lyrics */ = {{\n"
        "\t\t\tisa = PBXGroup;\n"
        "\t\t\tchildren = (\n"
        f"\t\t\t\t{lyrics_ref} /* {lyrics_name} */,\n"
        "\t\t\t);\n"
        "\t\t\tpath = Lyrics;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};\n"
    )
    planned = planned.replace(group_anchor, group_entry + group_anchor, 1)
    planned = planned.replace(child_anchor, child_anchor + f"\t\t\t\t{lyrics_group} /* Lyrics */,\n", 1)

source_entry = f"\t\t\t\t{lyrics_build} /* {lyrics_name} in Sources */,\n"
if source_entry not in planned:
    anchor = "\t\t\t\tED1000082F20000100000001 /* LyricFeverLyricsService.swift in Sources */,\n"
    require(planned, anchor, "lock-screen lyric Sources phase anchor")
    planned = planned.replace(anchor, anchor + source_entry, 1)

required_membership = [
    "ThermalDetailMonitor.swift in Sources",
    "BudsAppModel.swift in Sources",
    "LyricRomanizationService.swift in Sources",
    "LockScreenLyricLineView.swift in Sources",
]
for entry in required_membership:
    require(planned, entry, f"planned membership {entry}")

if planned != original:
    project.write_text(planned)
    print("Restored missing Xcode source membership")
else:
    print("Xcode source membership already correct")
