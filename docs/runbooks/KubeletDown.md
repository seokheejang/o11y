# KubeletDown

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `KubeletDown`
- Severity: `critical`
- Trigger: `absent(up{job="kubelet"} == 1)` for 15m

## Impact
해당 노드의 Pod 라이프사이클 관리 정지. 새 Pod 안 뜨고, health check 안 됨, 메트릭 collection 멈춤.

## Diagnosis
```bash
kubectl get nodes
kubectl describe node <node-name>
# 노드에 SSH 후:
systemctl status kubelet
journalctl -u kubelet -n 200
```

## Mitigation
1. `systemctl restart kubelet`.
2. 디스크/메모리 압박이면 해소.
3. 회복 안 되면 node drain + replace.

## Root cause
container runtime crash (containerd/CRI-O), kubelet 설정 오류, certificate 만료, 디스크 inode 고갈.
