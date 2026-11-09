"""CI guard: app/VERSION must be valid SemVer and a correct next step from the last release.

The last release is the newest image-v* git tag reachable from HEAD.
"""
import re
import subprocess
import sys
from pathlib import Path

SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
APP_CODE = ["app/", ":(exclude)app/VERSION", ":(exclude)app/test_*", ":(exclude)app/requirements-dev.txt"]


def check(previous, current, app_changed):
    """Return an error message, or None when VERSION is fine."""
    if not SEMVER.match(current):
        return f"VERSION '{current}' is not MAJOR.MINOR.PATCH"
    if previous is None:
        return None
    if current == previous:
        return "app code changed but VERSION was not bumped" if app_changed else None
    major, minor, patch = map(int, SEMVER.match(previous).groups())
    allowed = [f"{major}.{minor}.{patch + 1}", f"{major}.{minor + 1}.0", f"{major + 1}.0.0"]
    if current not in allowed:
        return f"{previous} -> {current} is not a valid next version (allowed: {', '.join(allowed)})"
    return None


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def main():
    current = Path("app/VERSION").read_text().strip()
    tag = git("describe", "--tags", "--abbrev=0", "--match", "image-v*")
    if tag.returncode != 0:
        previous, app_changed = None, True
    else:
        last = tag.stdout.strip()
        previous = git("show", f"{last}:app/VERSION").stdout.strip()
        app_changed = git("diff", "--quiet", last, "HEAD", "--", *APP_CODE).returncode != 0
    error = check(previous, current, app_changed)
    if error:
        sys.exit(f"VERSION check failed: {error}")
    print(f"VERSION check passed: {previous} -> {current}")


if __name__ == "__main__":
    main()
