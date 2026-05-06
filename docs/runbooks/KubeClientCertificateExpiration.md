# KubeClientCertificateExpiration

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `KubeClientCertificateExpiration`
- Severity: `critical` (24시간 이내)
- Trigger: API server client certificate가 24시간 안에 만료.

## Impact
인증서 만료 시 control plane 인증 깨짐 → API server / 컨트롤러 / kubelet 등 control plane 통신 실패.

## Diagnosis
```bash
# kubeadm 클러스터:
kubeadm certs check-expiration
# 매니지드(EKS/GKE/AKS)는 클라우드 콘솔의 인증서 갱신 정책 확인.
```

## Mitigation
1. kubeadm: `kubeadm certs renew all` → control plane 재시작.
2. 매니지드: 클라우드 자동 갱신 보통 — 미갱신 시 지원 ticket.
3. cert-manager 사용 환경이면 Issuer 상태 확인.

## Root cause
인증서 자동 갱신 실패 (cert-manager Issuer 다운, kubeadm cron 누락), 수동 발급 인증서가 갱신 미스.
