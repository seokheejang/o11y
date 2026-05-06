# CoreDNSDown

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `CoreDNSDown`
- Severity: `critical`
- Trigger: CoreDNS `up` 시리즈 부재 5m.

## Impact
**Service discovery 자체 다운**. 모든 in-cluster DNS 조회 실패 — Pod이 service 이름으로 다른 Pod 못 찾음. 클러스터 광범위 영향.

## Diagnosis
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl describe deploy -n kube-system coredns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100
# DNS 직접 테스트:
kubectl run dns-test --rm -it --image=busybox -- nslookup kubernetes.default
```

## Mitigation
1. CoreDNS deployment scale-up (보통 replicas=2).
2. Corefile (ConfigMap) 잘못 변경됐으면 rollback.
3. 노드 부족으로 scheduling 실패면 node 회복.

## Root cause
Corefile 설정 오류, upstream resolver 변경, RBAC 누락, OOM (limit 너무 작음), kube-system 노드 부족.
