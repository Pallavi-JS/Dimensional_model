#!/usr/bin/env bash
# Usage: ./run_all.sh [dbname]   (defaults to week5_dw). Needs psql + a running PostgreSQL.
set -euo pipefail
DB="${1:-week5_dw}"
mkdir -p output
createdb "$DB" 2>/dev/null || true
for f in sql/0*.sql; do
  echo ">>> $f"
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f" > "output/$(basename "${f%.sql}").txt"
done
echo "Done. Results are in ./output/"
