#!/bin/bash
echo "=== SQL Injection Test against WAF ==="
for payload in "' OR '1'='1" "' OR 1=1--" "admin'--" "' UNION SELECT * FROM users--"; do
  echo -n "Payload: $payload → "
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
    -X POST http://localhost:8080/ \
    -d "username=${payload}&password=test")
  echo "HTTP $CODE"
  sleep 1
done
echo "=== Done ==="
