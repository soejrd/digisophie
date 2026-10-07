#!/bin/sh
# Build the S033 Sophie release without redistributing firmware.
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 STOCK_DIGITAKT_OS_1.53_OR_1.54.syx ELEKLOADER_CHECKOUT" >&2
    exit 2
fi

stock=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
loader=$(cd "$2" && pwd)
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python=${PYTHON_BIN:-python3}

if [ ! -f "$stock" ] || [ ! -f "$loader/elekloader/sdk/build.py" ]; then
    echo "Expected a stock OS file and an elekloader source checkout." >&2
    exit 2
fi

# The OS the stock file is for: 1.54's files are named -os1.54, 1.53's are not.
os=$(PYTHONPATH="$loader${PYTHONPATH:+:$PYTHONPATH}" "$python" -c '
import sys
from elekloader import devices, syx
dev, rel = devices.identify(syx.Syx.load(sys.argv[1]).sha256)
print(rel.version)' "$stock")
case "$os" in
    1.53) suffix="" ;;
    1.54) suffix="-os1.54" ;;
    *) echo "Expected a Digitakt mk1 OS 1.53 or 1.54 file, not $os." >&2; exit 2 ;;
esac

cd "$loader"
"$python" -m elekloader.sdk.build mods/core --stock "$stock"
"$python" -m elekloader.sdk.build "$project" --stock "$stock"
(
    cd "$project/diagnostics/digihealth"
    PYTHONPATH="$loader${PYTHONPATH:+:$PYTHONPATH}" "$python" build.py --stock "$stock"
)

"$python" -m elekloader.lint --stock "$stock" \
    "$loader/mods/core/out/core-2.1$suffix.elemod" \
    "$project/diagnostics/digihealth/out/digihealth-1.0.1$suffix.elemod" \
    "$project/out/digisophie-1.1.13$suffix.elemod"
"$python" -m elekloader.patch --stock "$stock" \
    --mod "$loader/mods/core/out/core-2.1$suffix.elemod" \
    --mod "$project/diagnostics/digihealth/out/digihealth-1.0.1$suffix.elemod" \
    --mod "$project/out/digisophie-1.1.13$suffix.elemod" \
    --out "$project/out/Digitakt_OS${os}_SOPHIE_S033.syx" --version S033
