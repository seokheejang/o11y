# HighOOMKillRate

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `HighOOMKillRate`
- Severity: `critical`
- Trigger: `sum(increase(container_oom_events_total[5m])) > 3` for 5m

## Impact
5분 동안 OOMKill 다수 발생. 영향받는 워크로드는 자동 재시작되지만 반복되면 사용자 영향 발생, 메모리 누수 또는 limit 잘못 가능.

## Diagnosis
```bash
# 어떤 Pod가 OOMKill되고 있는지:
kubectl get events -A --sort-by=.lastTimestamp | grep -i oom
# Pod 단위 OOM:
kubectl get pods -A -o json | jq '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason=="OOMKilled") | .metadata.namespace + "/" + .metadata.name'
# 메모리 사용 추이 (Grafana):
container_memory_working_set_bytes / container_spec_memory_limit_bytes
```

## Mitigation
1. 임시: limit 상향 (Deployment edit) — root cause 해결 아님.
2. 누수 의심: heap profile / pprof.
3. requests/limits 잘못 잡혔으면 VPA 추천값 또는 부하 테스트 기반 재계산.

## Root cause
실제 메모리 누수, request 너무 낮아 OOM, limit 너무 낮아 normal usage에서 OOM, traffic 증가에 따른 working set 증가.
