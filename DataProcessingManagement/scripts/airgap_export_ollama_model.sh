#!/usr/bin/env bash
# Export ONE Ollama model (manifest + its blob layers) for air-gapped transfer.
# Usage: airgap_export_ollama_model.sh <model[:tag]> <out_dir>
#   e.g. airgap_export_ollama_model.sh qwen3.5:4b /d/airgap-bundle/ollama/models
set -euo pipefail

MODEL="${1:?model name, e.g. qwen3.5:4b}"
OUT="${2:?output dir}"
MODELS="${OLLAMA_MODELS:-$USERPROFILE/.ollama/models}"

name="${MODEL%%:*}"; tag="${MODEL#*:}"; [ "$tag" = "$MODEL" ] && tag="latest"
# library models live under registry.ollama.ai/library/<name>/<tag>
mani="$MODELS/manifests/registry.ollama.ai/library/$name/$tag"
[ -f "$mani" ] || mani="$MODELS/manifests/registry.ollama.ai/$name/$tag"
[ -f "$mani" ] || { echo "manifest not found for $MODEL under $MODELS" >&2; exit 1; }

rel="${mani#$MODELS/}"
mkdir -p "$OUT/$(dirname "$rel")" "$OUT/blobs"
cp "$mani" "$OUT/$rel"

python - "$mani" <<'PY' | while read -r d; do
import json,sys
m=json.load(open(sys.argv[1]))
print(m["config"]["digest"])
for l in m["layers"]: print(l["digest"])
PY
  f="sha256-${d#sha256:}"
  cp "$MODELS/blobs/$f" "$OUT/blobs/$f"
  echo "  blob $f"
done
echo "exported $MODEL -> $OUT"
du -sh "$OUT"
