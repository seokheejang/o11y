# KubeNodeNotReady

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `KubeNodeNotReady`
- Severity: `critical`
- Trigger: `kube_node_status_condition{condition="Ready",status="true"} == 0` for 15m

## Impact
해당 노드의 모든 Pod가 영향. Ready 상태가 아니면 K8s가 자동 evict 시작 — 다른 노드로 재배치되지만 그동안 사용자 영향 발생 가능.

## Diagnosis
```bash
kubectl describe node <node-name>
kubectl get events --sort-by=.lastTimestamp | grep <node-name>
# kubelet 로그:
journalctl -u kubelet -n 200    # 노드 SSH 후
```

## Mitigation
1. kubelet 재시작 (`systemctl restart kubelet`).
2. 디스크 압박이면 정리, 메모리 압박이면 노이즈 Pod 제거.
3. 회복 안 되면 노드 cordon + drain + replace.

## Root cause
kubelet 다운, container runtime 장애, 디스크 full, 네트워크 단절, kernel panic.
