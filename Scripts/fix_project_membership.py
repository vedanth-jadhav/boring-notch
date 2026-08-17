from pathlib import Path

project = Path('boringNotch.xcodeproj/project.pbxproj')
s = project.read_text()

# Remove the temporary compatibility shim now that the repository's real thermal monitor
# is restored to the target.
stats = Path('boringNotch/managers/SystemStatsMonitor.swift')
stats_source = stats.read_text()
marker = '\n// MARK: - Thermal detail snapshot\n'
if marker in stats_source:
    stats.write_text(stats_source.split(marker, 1)[0].rstrip() + '\n')

files = [
    ('A70000012F30000100000001', 'A70100012F30000100000001', 'ThermalDetailMonitor.swift'),
    ('A70000022F30000100000001', 'A70100022F30000100000001', 'ANCWireMapping.swift'),
    ('A70000032F30000100000001', 'A70100032F30000100000001', 'BudsAppModel.swift'),
    ('A70000042F30000100000001', 'A70100042F30000100000001', 'BudsClassicBluetoothMonitor.swift'),
    ('A70000052F30000100000001', 'A70100052F30000100000001', 'BudsClient.swift'),
    ('A70000062F30000100000001', 'A70100062F30000100000001', 'BudsModels.swift'),
    ('A70000072F30000100000001', 'A70100072F30000100000001', 'BudsUtils.swift'),
    ('A70000082F30000100000001', 'A70100082F30000100000001', 'OPOProtocol.swift'),
    ('A70000092F30000100000001', 'A70100092F30000100000001', 'BudsNotchView.swift'),
    ('A700000A2F30000100000001', 'A701000A2F30000100000001', 'LyricRomanizationService.swift'),
]

if 'A70000012F30000100000001' not in s:
    build_entries = ''.join(
        f'\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n'
        for ref, build, name in files
    )
    s = s.replace('/* End PBXBuildFile section */', build_entries + '/* End PBXBuildFile section */', 1)

    ref_entries = ''.join(
        f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n'
        for ref, _, name in files
    )
    s = s.replace('/* End PBXFileReference section */', ref_entries + '/* End PBXFileReference section */', 1)

    groups = '''\t\tA70200012F30000100000001 /* Buds */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\tA70000022F30000100000001 /* ANCWireMapping.swift */,\n\t\t\t\tA70000032F30000100000001 /* BudsAppModel.swift */,\n\t\t\t\tA70000042F30000100000001 /* BudsClassicBluetoothMonitor.swift */,\n\t\t\t\tA70000052F30000100000001 /* BudsClient.swift */,\n\t\t\t\tA70000062F30000100000001 /* BudsModels.swift */,\n\t\t\t\tA70000072F30000100000001 /* BudsUtils.swift */,\n\t\t\t\tA70000082F30000100000001 /* OPOProtocol.swift */,\n\t\t\t);\n\t\t\tpath = Buds;\n\t\t\tsourceTree = "<group>";\n\t\t};\n\t\tA70200022F30000100000001 /* Buds */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\tA70000092F30000100000001 /* BudsNotchView.swift */,\n\t\t\t);\n\t\t\tpath = Buds;\n\t\t\tsourceTree = "<group>";\n\t\t};\n\t\tA70200032F30000100000001 /* services */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\tA700000A2F30000100000001 /* LyricRomanizationService.swift */,\n\t\t\t);\n\t\t\tpath = services;\n\t\t\tsourceTree = "<group>";\n\t\t};\n'''
    s = s.replace('/* End PBXGroup section */', groups + '/* End PBXGroup section */', 1)

    manager_anchor = '\t\t\t\tED0000182F10000100000001 /* SystemStatsMonitor.swift */,\n'
    s = s.replace(
        manager_anchor,
        manager_anchor + '\t\t\t\tA70000012F30000100000001 /* ThermalDetailMonitor.swift */,\n\t\t\t\tA70200012F30000100000001 /* Buds */,\n',
        1,
    )

    components_anchor = '\t\t\t\tED00001A2F10000100000001 /* System */,\n'
    s = s.replace(
        components_anchor,
        components_anchor + '\t\t\t\tA70200022F30000100000001 /* Buds */,\n',
        1,
    )

    root_anchor = '\t\t\t\t147163B52C5D804B0068B555 /* managers */,\n'
    s = s.replace(
        root_anchor,
        root_anchor + '\t\t\t\tA70200032F30000100000001 /* services */,\n',
        1,
    )

    source_entries = ''.join(
        f'\t\t\t\t{build} /* {name} in Sources */,\n' for _, build, name in files
    )
    phase_anchor = '\t\t\t\t1471639A2C5D35FF0068B555 /* MusicManager.swift in Sources */,\n'
    if phase_anchor not in s:
        raise SystemExit('boringNotch Sources phase anchor not found')
    s = s.replace(phase_anchor, source_entries + phase_anchor, 1)

# Restore the extracted lock-screen lyric line view to the application target. The
# source file already exists in the repository, but older project files omitted it.
lyrics_ref = 'ED1000192F20000100000001'
lyrics_build = 'ED1000092F20000100000001'
lyrics_group = 'ED1000232F20000100000001'
lyrics_name = 'LockScreenLyricLineView.swift'

if f'{lyrics_build} /* {lyrics_name} in Sources */' not in s:
    build_anchor = '\t\tED1000082F20000100000001 /* LyricFeverLyricsService.swift in Sources */ = {isa = PBXBuildFile; fileRef = ED1000182F20000100000001 /* LyricFeverLyricsService.swift */; };\n'
    build_entry = f'\t\t{lyrics_build} /* {lyrics_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {lyrics_ref} /* {lyrics_name} */; }};\n'
    if build_anchor not in s:
        raise SystemExit('Lock-screen lyric build-file anchor not found')
    s = s.replace(build_anchor, build_anchor + build_entry, 1)

# Check for the declaration itself, not any incidental reference to the ID from a
# build-file/group entry. The old loose check could leave a dangling PBXBuildFile.
if f'{lyrics_ref} /* {lyrics_name} */ = {{isa = PBXFileReference;' not in s:
    ref_anchor = '\t\tED1000182F20000100000001 /* LyricFeverLyricsService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LyricFeverLyricsService.swift; sourceTree = "<group>"; };\n'
    ref_entry = f'\t\t{lyrics_ref} /* {lyrics_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {lyrics_name}; sourceTree = "<group>"; }};\n'
    if ref_anchor not in s:
        raise SystemExit('Lock-screen lyric file-reference anchor not found')
    s = s.replace(ref_anchor, ref_anchor + ref_entry, 1)

if f'{lyrics_group} /* Lyrics */' not in s:
    group_entry = (
        f'\t\t{lyrics_group} /* Lyrics */ = {{\n'
        '\t\t\tisa = PBXGroup;\n'
        '\t\t\tchildren = (\n'
        f'\t\t\t\t{lyrics_ref} /* {lyrics_name} */,\n'
        '\t\t\t);\n'
        '\t\t\tpath = Lyrics;\n'
        '\t\t\tsourceTree = "<group>";\n'
        '\t\t};\n'
    )
    group_anchor = '\t\tED1000202F20000100000001 /* LockScreen */ = {\n'
    if group_anchor not in s:
        raise SystemExit('Components Lyrics group anchor not found')
    s = s.replace(group_anchor, group_entry + group_anchor, 1)

    components_anchor = '\t\t\t\tED1000202F20000100000001 /* LockScreen */,\n'
    if components_anchor not in s:
        raise SystemExit('Components child anchor for Lyrics not found')
    s = s.replace(components_anchor, components_anchor + f'\t\t\t\t{lyrics_group} /* Lyrics */,\n', 1)

source_entry = f'\t\t\t\t{lyrics_build} /* {lyrics_name} in Sources */,\n'
if source_entry not in s:
    source_anchor = '\t\t\t\tED1000082F20000100000001 /* LyricFeverLyricsService.swift in Sources */,\n'
    if source_anchor not in s:
        raise SystemExit('Lock-screen lyric Sources phase anchor not found')
    s = s.replace(source_anchor, source_anchor + source_entry, 1)

# The Octave controller is observed and mutated on the main queue/main actor. Combine's
# receive(on:) guarantee is runtime-only, so Swift 6 cannot prove the reference captured by
# the asynchronous tab detector is safe. Declare that narrow controller Sendable explicitly
# rather than carrying a Swift-6-error warning in an otherwise clean build.
now_playing = Path('boringNotch/MediaControllers/NowPlayingController.swift')
now_playing_source = now_playing.read_text()
octave_decl = 'final class OctaveStreamingController: ObservableObject, MediaControllerProtocol {'
octave_sendable_decl = 'final class OctaveStreamingController: ObservableObject, MediaControllerProtocol, @unchecked Sendable {'
if octave_decl in now_playing_source:
    now_playing.write_text(now_playing_source.replace(octave_decl, octave_sendable_decl, 1))
elif octave_sendable_decl not in now_playing_source:
    raise SystemExit('OctaveStreamingController declaration not found')

project.write_text(s)
print('Restored Buds, romanization, thermal, and lock-screen lyric sources to boringNotch target')
