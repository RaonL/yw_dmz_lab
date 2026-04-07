#!/bin/bash
echo "=== XSS Test against WAF ==="
for payload in "<script>alert(1)</script>" "<img src=x onerror=alert(1)>" "<svg/onload=alert(1)>"; do
  echo -n "Payload: $payload → "
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
    -X POST http://localhost:8080/ \
    -d "username=${payload}&password=test")
  echo "HTTP $CODE"
  sleep 1
done
echo "=== Done ==="
