# PrometheusRuleFailures

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.
> **메타 알림**: 이 알림이 울리면 *다른 알림이 안 울릴 수 있다*는 뜻.

## Symptom
- Alert: `PrometheusRuleFailures`
- Severity: `critical`
- Trigger: `increase(prometheus_rule_evaluation_failures_total[5m]) > 0` for 5m

## Impact
Prometheus의 rule 평가가 실패 중. 일부 알림이 발화 못 하거나 recording rule이 멈춤 → **알림 시스템 자체의 신뢰성 저하**.

## Diagnosis
```bash
# Prometheus UI → Status → Rules에서 빨간색 그룹 찾기.
kubectl port-forward -n monitoring svc/<prom-svc> 9090
# 실패 룰을 PromQL로:
prometheus_rule_evaluation_failures_total > 0
# Prometheus pod 로그:
kubectl logs -n monitoring sts/<prom-sts> -c prometheus --tail=200 | grep -i "rule.*fail\|invalid"
```

## Mitigation
1. 실패한 룰의 PromQL 표현식 syntax 검증 (`promtool check rules`).
2. 의존하는 메트릭 시리즈 부재면 표현식에 `or vector(0)` 가드 추가 검토.
3. cardinality 폭발이면 `topk` / 라벨 필터링.

## Root cause
PromQL 함수 시그니처 변화 (Prometheus 업그레이드), 의존 메트릭 부재, cardinality 폭발, recording rule 의존성 끊김.
