# KubePersistentVolumeErrors

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `KubePersistentVolumeErrors`
- Severity: `critical`
- Trigger: `kube_persistentvolume_status_phase{phase=~"Failed|Pending"} > 0` for 5m

## Impact
PV가 Failed/Pending이면 그 PV에 의존하는 Pod가 시작 못 함 (StatefulSet 새 인스턴스, 신규 배포 등).

## Diagnosis
```bash
kubectl get pv | grep -E 'Failed|Pending'
kubectl describe pv <pv-name>
# CSI 드라이버 로그:
kubectl logs -n kube-system -l app=<csi-driver> --tail=100
```

## Mitigation
1. provisioner 오류 메시지 확인. 클라우드 디스크 quota 초과면 quota 증액.
2. CSI 드라이버 Pod 재시작.
3. Failed PV는 보통 수동 삭제 후 재생성.

## Root cause
StorageClass 설정 오류, 클라우드 quota, provisioner 다운, AZ 불일치, IAM 권한 부족.
