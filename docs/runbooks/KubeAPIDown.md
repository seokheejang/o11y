# KubeAPIDown

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `KubeAPIDown`
- Severity: `critical`
- Trigger: `absent(up{job="apiserver"} == 1)` for 15m

## Impact
Kubernetes API server 자체 부재. control plane 동작 정지 — `kubectl`·operator·controller 모두 실패. 클러스터 운영 불가.

## Diagnosis
- 클라우드 제공자(EKS/GKE/AKS)인 경우 콘솔에서 control plane 상태 확인.
- on-prem이면 etcd cluster 건강도 먼저 (`etcdctl endpoint status`).
- 네트워크: control plane LB / VIP 도달 가능한지.
- API server pod 로그(존재 시): `kubectl logs -n kube-system kube-apiserver-*` (자가 호스팅 한정).

## Mitigation
1. 매니지드 클러스터: 클라우드 지원에 ticket.
2. 자가 호스팅: API server 컨테이너/시스템 서비스 재시작.
3. 인증서 만료 의심 시 `KubeClientCertificateExpiration` 룬북 참조.

## Root cause
주요 패턴: 인증서 만료, etcd 장애, control plane 노드 OOM, 네트워크 분할.
