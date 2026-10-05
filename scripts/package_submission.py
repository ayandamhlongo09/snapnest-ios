#!/usr/bin/env python3
"""Archive tracked source and genuine Git history. Never include simulator diagnostic bundles."""
import pathlib, subprocess, zipfile
root = pathlib.Path(__file__).resolve().parents[1]
output = root / 'submission' / 'SnapNest-assessment.zip'
output.parent.mkdir(exist_ok=True)
paths = [root / name for name in subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0') if name]
paths += [path for path in (root / '.git').rglob('*') if path.is_file() and not path.name.endswith('.lock')]
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(set(paths)):
        archive.write(path, pathlib.Path('SnapNest') / path.relative_to(root))
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert 'SnapNest/.git/HEAD' in archive.namelist()
    assert 'SnapNest/demo/SnapNest-demo.mov' in archive.namelist()
print(f'{output} ({output.stat().st_size:,} bytes, includes .git)')
