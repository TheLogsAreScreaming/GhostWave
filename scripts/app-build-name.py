#!/usr/bin/env python3
"""Print the version name for the next app build: 0.1.0-dev.N, one past the
highest app-v0.1.0-dev.N tag on GhostWave-Releases (git tags, which outlive
deleted releases). Used by .github/workflows/app.yml."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
print(release.next_app_version(release.git_tags()))
