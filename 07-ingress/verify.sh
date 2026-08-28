#!/usr/bin/env bash
# CKA 7강 자동 채점 스크립트 — Ingress와 보안 기초
set -uo pipefail

PASS=0; FAIL=0

check() {
  local desc="$1"; local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo "  [PASS] $desc"; ((PASS++))
  else
    echo "  [FAIL] $desc"; ((FAIL++))
  fi
}

check_output() {
  local desc="$1"; local cmd="$2"; local expect="$3"
  local out
  out=$(eval "$cmd" 2>/dev/null || true)
  if echo "$out" | grep -q "$expect"; then
    echo "  [PASS] $desc"; ((PASS++))
  else
    echo "  [FAIL] $desc (기대값: '$expect', 실제: '$(echo "$out" | head -1)')"
    ((FAIL++))
  fi
}

echo "================================================="
echo " CKA 7강 채점 — Ingress와 보안 기초"
echo "================================================="
echo ""

# ── P1: 기본 Ingress ──────────────────────────────────
echo "[P1] 기본 Ingress — Deployment + Service + Ingress"

check "web1 Deployment 존재" \
  "kubectl get deployment web1 -n default"

check_output "web1 Deployment READY" \
  "kubectl get deployment web1 -n default --no-headers" \
  "[1-9]/[1-9]"

check "web1-svc Service 존재" \
  "kubectl get service web1-svc -n default"

check_output "web1-svc ClusterIP 타입 확인" \
  "kubectl get service web1-svc -n default -o jsonpath='{.spec.type}'" \
  "ClusterIP"

check "web-ingress Ingress 존재" \
  "kubectl get ingress web-ingress -n default"

check_output "web-ingress path /web1 존재" \
  "kubectl get ingress web-ingress -n default -o jsonpath='{.spec.rules[0].http.paths[0].path}'" \
  "/web1"

check_output "web-ingress backend service=web1-svc" \
  "kubectl get ingress web-ingress -n default -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'" \
  "web1-svc"

check_output "web-ingress backend port=80" \
  "kubectl get ingress web-ingress -n default -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}'" \
  "80"

echo ""

# ── P2: 호스트 기반 Ingress ───────────────────────────
echo "[P2] 호스트 기반 Ingress — myapp.local"

check "host-ingress Ingress 존재" \
  "kubectl get ingress host-ingress -n default"

check_output "host-ingress host=myapp.local 존재" \
  "kubectl get ingress host-ingress -n default -o jsonpath='{.spec.rules[0].host}'" \
  "myapp.local"

check_output "host-ingress backend service=web1-svc" \
  "kubectl get ingress host-ingress -n default -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'" \
  "web1-svc"

echo ""

# ── P3: TLS Ingress ───────────────────────────────────
echo "[P3] TLS Ingress — HTTPS 설정"

check "tls-secret Secret 존재" \
  "kubectl get secret tls-secret -n default"

check_output "tls-secret type=kubernetes.io/tls 확인" \
  "kubectl get secret tls-secret -n default -o jsonpath='{.type}'" \
  "kubernetes.io/tls"

check_output "tls-secret에 tls.crt 키 존재" \
  "kubectl get secret tls-secret -n default -o jsonpath='{.data.tls\\.crt}'" \
  "."

check_output "tls-secret에 tls.key 키 존재" \
  "kubectl get secret tls-secret -n default -o jsonpath='{.data.tls\\.key}'" \
  "."

# tls-ingress 존재 여부 (이름이 다를 수 있으므로 tls 설정을 가진 ingress 탐색)
TLS_INGRESS_COUNT=$(kubectl get ingress -n default -o jsonpath='{range .items[*]}{.spec.tls}{"\n"}{end}' 2>/dev/null | grep -v "^$" | wc -l || echo "0")
if [[ "$TLS_INGRESS_COUNT" -gt 0 ]]; then
  echo "  [PASS] TLS 설정이 있는 Ingress 존재"; ((PASS++))
else
  echo "  [FAIL] TLS 설정이 있는 Ingress 없음 (spec.tls[] 확인)"; ((FAIL++))
fi

check_output "Ingress TLS secretName=tls-secret 참조" \
  "kubectl get ingress -n default -o jsonpath='{range .items[*]}{.spec.tls[*].secretName}{\" \"}{end}'" \
  "tls-secret"

echo ""

# ── P4: NetworkPolicy ─────────────────────────────────
echo "[P4] NetworkPolicy — Zero Trust 격리 (production)"

check "production 네임스페이스 존재" \
  "kubectl get namespace production"

check "secure-app Deployment 존재 (production)" \
  "kubectl get deployment secure-app -n production"

check_output "secure-app Deployment READY" \
  "kubectl get deployment secure-app -n production --no-headers" \
  "[1-9]/[1-9]"

NP_COUNT=$(kubectl get networkpolicy -n production --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$NP_COUNT" -ge 1 ]]; then
  echo "  [PASS] production에 NetworkPolicy 존재 (${NP_COUNT}개)"; ((PASS++))
else
  echo "  [FAIL] production에 NetworkPolicy 없음"; ((FAIL++))
fi

# Default Deny 정책 확인: policyTypes에 Ingress가 있고 ingress 규칙이 없는 정책
DENY_EXISTS=$(kubectl get networkpolicy -n production -o json 2>/dev/null | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
  spec = item.get('spec', {})
  pt = spec.get('policyTypes', [])
  ing = spec.get('ingress', None)
  sel = spec.get('podSelector', {})
  # podSelector: {} AND policyTypes includes Ingress AND no ingress rules = default deny
  if 'Ingress' in pt and ing is None and sel.get('matchLabels', None) is None:
    print('found')
    break
" 2>/dev/null || true)

if [[ "$DENY_EXISTS" == "found" ]]; then
  echo "  [PASS] Default Deny NetworkPolicy 확인 (podSelector:{}, policyTypes:[Ingress], ingress 규칙 없음)"; ((PASS++))
else
  echo "  [FAIL] Default Deny NetworkPolicy 없음 (podSelector:{} + policyTypes:[Ingress] + ingress 규칙 없는 정책 필요)"; ((FAIL++))
fi

# port 8080 허용 정책 확인
ALLOW_8080=$(kubectl get networkpolicy -n production -o json 2>/dev/null | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
  spec = item.get('spec', {})
  for ing in spec.get('ingress', []):
    for p in ing.get('ports', []):
      if str(p.get('port', '')) == '8080':
        print('found')
        sys.exit(0)
" 2>/dev/null || true)

if [[ "$ALLOW_8080" == "found" ]]; then
  echo "  [PASS] port 8080 허용 NetworkPolicy 확인"; ((PASS++))
else
  echo "  [FAIL] port 8080 허용 NetworkPolicy 없음 (ingress[].ports[].port: 8080 필요)"; ((FAIL++))
fi

echo ""
echo "================================================="
echo " 결과: ${PASS}개 통과 / $((PASS + FAIL))개 전체"
if [[ $FAIL -eq 0 ]]; then
  echo " 전체 통과! 7강 실습 완료."
else
  echo " ${FAIL}개 미통과 — 위 항목을 확인하세요."
fi
echo "================================================="
