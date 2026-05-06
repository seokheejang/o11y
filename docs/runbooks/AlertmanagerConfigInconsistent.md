# AlertmanagerConfigInconsistent

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `AlertmanagerConfigInconsistent`
- Severity: `critical`
- Trigger: HA Alertmanager 인스턴스 간 `alertmanager_config_hash`가 분기.

## Impact
HA replicas의 설정이 다름 → 같은 알림이 중복 발송되거나 한 쪽에서 라우팅 실패. 노이즈 또는 누락.

## Diagnosis
```bash
# 어떤 인스턴스가 다른 hash를 갖는지:
kubectl exec -n monitoring sts/alertmanager-main-0 -c alertmanager -- amtool config show
# 모든 인스턴스에서 amtool 실행 후 비교.
```

## Mitigation
1. ConfigMap/Secret reload 강제 (operator 사용 시 reconcile loop 트리거).
2. Alertmanager Pod 순차 재시작.
3. operator가 reconcile 못 하면 `alertmanager_config_hash` 메트릭이 같아질 때까지 수동 sync.

## Root cause
operator reconcile lag, ConfigMap/Secret 수동 수정 후 sync 실패, network partition으로 gossip 지연.
