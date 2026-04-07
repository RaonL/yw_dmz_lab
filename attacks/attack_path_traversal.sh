#!/bin/bash
echo "=== Directory Traversal Test ==="
for path in "../../../../etc/passwd" "../../../etc/shadow" "....//....//etc/passwd"; do
  echo -n "Path: $path → "
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
    "http://localhost:8080/${path}")
  echo "HTTP $CODE"
  sleep 1
done
echo "=== Done ==="
