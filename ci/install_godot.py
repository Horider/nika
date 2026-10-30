from pathlib import Path
import urllib.request, hashlib, zipfile
version='4.7.2'
base=f'https://github.com/godotengine/godot-builds/releases/download/{version}-stable/'
cache=Path('.cache');cache.mkdir(exist_ok=True)
sums=urllib.request.urlopen(base+'SHA512-SUMS.txt').read().decode()
hashes={line.split()[1].lstrip('*'):line.split()[0] for line in sums.splitlines() if line.strip()}
for name in [f'Godot_v{version}-stable_linux.x86_64.zip',f'Godot_v{version}-stable_export_templates.tpz']:
    target=cache/name;urllib.request.urlretrieve(base+name,target)
    with target.open('rb') as f: actual=hashlib.file_digest(f,'sha512').hexdigest()
    assert actual==hashes[name], 'Official checksum mismatch'
    with zipfile.ZipFile(target) as z:
        if name.endswith('.tpz'):
            dest=Path.home()/'.local/share/godot/export_templates'/f'{version}.stable';dest.mkdir(parents=True,exist_ok=True)
            for item in z.namelist():
                if item.endswith(('web_nothreads_debug.zip','web_nothreads_release.zip')): (dest/Path(item).name).write_bytes(z.read(item))
        else:
            binary=next(n for n in z.namelist() if n.endswith('linux.x86_64'));(cache/'godot').write_bytes(z.read(binary));(cache/'godot').chmod(0o755)
