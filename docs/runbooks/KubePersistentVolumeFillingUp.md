# KubePersistentVolumeFillingUp

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `KubePersistentVolumeFillingUp`
- Severity: `critical` (3% 이하 + 4일 내 가득 찰 예측)
- Trigger: `kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes < 0.03 and predict_linear(... [6h], 4*24*3600) < 0` for 1h

## Impact
PVC 사용 워크로드(DB / StatefulSet)가 가득 차면 쓰기 실패 → 애플리케이션 에러, 데이터 손실 가능.

## Diagnosis
```bash
kubectl get pvc -A
# 어떤 Pod가 사용 중인지:
kubectl get pods -n <ns> -o wide | grep <pvc-related-pod>
# 사용량 큰 디렉토리 추적:
kubectl exec -n <ns> <pod> -- du -sh /<mount> 2>/dev/null | sort -h
```

## Mitigation
1. 임시: 사용량 큰 파일 정리 (로그 rotation, 오래된 백업).
2. 영구: PVC resize (`kubectl edit pvc` — StorageClass가 `allowVolumeExpansion: true` 여야 함).
3. CSI 드라이버가 online resize 지원 안 하면 Pod 재시작 필요.

## Root cause
로그 rotation 미설정, 백업 정책 부재, retention 너무 김, traffic 증가에 따른 자연 증가.
