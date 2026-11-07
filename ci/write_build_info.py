from pathlib import Path
import hashlib, json, subprocess
root = Path(__file__).resolve().parents[1]
data = {
    "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
    "days": list(range(1, 11)),
    "save_schema": 10,
    "story_sha256": hashlib.sha256((root / "game/data/story.json").read_bytes()).hexdigest(),
    "text_sha256": hashlib.sha256((root / "game/data/text.json").read_bytes()).hexdigest(),
}
(root / "web/build-info.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
