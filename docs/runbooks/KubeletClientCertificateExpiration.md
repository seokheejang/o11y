# KubeletClientCertificateExpiration

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `KubeletClientCertificateExpiration`
- Severity: `critical` (24시간 이내)
- Trigger: kubelet client certificate가 24시간 안에 만료.

## Impact
kubelet이 API server에 인증 못 함 → 노드가 NotReady로 전환, Pod 관리 정지.

## Diagnosis
```bash
# 노드에 SSH 후:
ls -la /var/lib/kubelet/pki/
openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -dates
# RotateKubeletClientCertificate feature gate 활성 확인:
ps aux | grep kubelet | grep -o 'RotateKubelet[^ ]*'
```

## Mitigation
1. `RotateKubeletClientCertificate=true` 활성 → kubelet 자동 갱신 (재시작 필요할 수도).
2. 비활성 환경이면 새 CSR 수동 승인.

## Root cause
RotateKubeletClientCertificate feature 미활성, kubelet ↔ API server 통신 단절로 갱신 실패, CSR auto-approver 다운.
