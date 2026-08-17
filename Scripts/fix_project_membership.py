from pathlib import Path
import subprocess

patch = Path("Scripts/review_fixes.patch")
if not patch.is_file():
    raise SystemExit("Verified review patch is missing")

subprocess.run(["git", "apply", "--check", str(patch)], check=True)
subprocess.run(["git", "apply", str(patch)], check=True)
subprocess.run(["git", "diff", "--check"], check=True)

paths = [
    "boringNotch/MediaControllers/NowPlayingController.swift",
    "boringNotch/managers/Lyrics/LyricFeverLyricsService.swift",
    "boringNotch/managers/MusicManager.swift",
    "boringNotch/MediaControllers/MediaControllerProtocol.swift",
    "boringNotch/components/Onboarding/MusicControllerSelectionView.swift",
    "boringNotch/Info.plist",
    "boringNotch.xcodeproj/project.pbxproj",
]
subprocess.run(["git", "config", "user.name", "github-actions[bot]"], check=True)
subprocess.run(["git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"], check=True)
subprocess.run(["git", "add", *paths], check=True)
subprocess.run(["git", "commit", "-m", "Apply verified review fixes"], check=True)
print("Applied verified review patch; reusable workflow will push and build it")
