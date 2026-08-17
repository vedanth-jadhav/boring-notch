from pathlib import Path

thermal = Path("boringNotch/managers/ThermalDetailMonitor.swift")
if not thermal.is_file():
    raise SystemExit("Standalone ThermalDetailMonitor.swift is missing")

print("Standalone thermal monitor source present")
