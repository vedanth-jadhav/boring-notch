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

    # Three new logical groups match the existing repository layout.
    groups = '''\t\tA70200012F30000100000001 /* Buds */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\tA70000022F30000100000001 /* ANCWireMapping.swift */,\n\t\t\t\tA70000032F30000100000001 /* BudsAppModel.swift */,\n\t\t\t\tA70000042F30000100000001 /* BudsClassicBluetoothMonitor.swift */,\n\t\t\t\tA70000052F30000100000001 /* BudsClient.swift */,\n\t\t\t\tA70000062F30000100000001 /* BudsModels.swift */,\n\t\t\t\tA70000072F30000100000001 /* BudsUtils.swift */,\n\t\t\t\tA70000082F30000100000001 /* OPOProtocol.swift */,\n\t\t\t);\n\t\t\tpath = Buds;\n\t\t\tsourceTree = "<group>";\n\t\t};\n\t\tA70200022F30000100000001 /* Buds */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\tA70000092F30000100000001 /* BudsNotchView.swift */,\n\t\t\t);\n\t\t\tpath = Buds;\n\t\t\tsourceTree = "<group>";\n\t\t};\n\t\tA70200032F30000100000001 /* services */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\tA700000A2F30000100000001 /* LyricRomanizationService.swift */,\n\t\t\t);\n\t\t\tpath = services;\n\t\t\tsourceTree = "<group>";\n\t\t};\n'''
    s = s.replace('/* End PBXGroup section */', groups + '/* End PBXGroup section */', 1)

    # Existing managers group: real thermal monitor plus Buds manager subtree.
    manager_anchor = '\t\t\t\tED0000182F10000100000001 /* SystemStatsMonitor.swift */,\n'
    s = s.replace(
        manager_anchor,
        manager_anchor + '\t\t\t\tA70000012F30000100000001 /* ThermalDetailMonitor.swift */,\n\t\t\t\tA70200012F30000100000001 /* Buds */,\n',
        1,
    )

    # Existing components group: Buds view subtree.
    components_anchor = '\t\t\t\tED00001A2F10000100000001 /* System */,\n'
    s = s.replace(
        components_anchor,
        components_anchor + '\t\t\t\tA70200022F30000100000001 /* Buds */,\n',
        1,
    )

    # Root application group: services subtree.
    root_anchor = '\t\t\t\t147163B52C5D804B0068B555 /* managers */,\n'
    s = s.replace(
        root_anchor,
        root_anchor + '\t\t\t\tA70200032F30000100000001 /* services */,\n',
        1,
    )

    source_entries = ''.join(
        f'\t\t\t\t{build} /* {name} in Sources */,\n' for _, build, name in files
    )
    # Insert into the boringNotch Sources phase, immediately before an existing known source.
    phase_anchor = '\t\t\t\t1471639A2C5D35FF0068B555 /* MusicManager.swift in Sources */,\n'
    if phase_anchor not in s:
        raise SystemExit('boringNotch Sources phase anchor not found')
    s = s.replace(phase_anchor, source_entries + phase_anchor, 1)

project.write_text(s)
print('Restored Buds, romanization, and thermal sources to boringNotch target')
