# IngressControllerDown

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `IngressControllerDown`
- Severity: `critical`
- Trigger: ingress controller `up` 시리즈 부재 5m.

## Impact
**외부 트래픽 진입점 다운**. 이 controller로 라우팅되는 모든 사용자 요청 실패.

## Diagnosis
```bash
kubectl get pods -n <ingress-ns>
kubectl describe deploy -n <ingress-ns> <controller>
kubectl logs -n <ingress-ns> -l app.kubernetes.io/component=controller --tail=100
# Service / Endpoint 상태:
kubectl get svc,ep -n <ingress-ns>
```

## Mitigation
1. controller deployment scale-up.
2. CrashLoop이면 직전 commit/values 변경 확인 — rollback.
3. LoadBalancer service 외부 IP 부착 안 됐으면 cloud-controller 확인.

## Root cause
설정 errror (잘못된 ConfigMap), TLS cert 누락, RBAC 권한 부족, 노드 부족으로 scheduling 실패, 클라우드 LB 할당 실패.
