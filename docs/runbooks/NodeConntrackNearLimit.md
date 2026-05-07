# NodeConntrackNearLimit

> Stub — 사고 발생 시 실제 진단·완화 노하우로 채운다.

## Symptom
- Alert: `NodeConntrackNearLimit`
- Severity: `critical`
- Trigger: `node_nf_conntrack_entries / node_nf_conntrack_entries_limit > 0.8` for 10m

## Impact
노드 conntrack 테이블 80%+ 점유. 한도 도달 시 신규 connection 드롭 — Pod ↔ Pod, 외부 API 호출, DNS UDP 응답 모두 영향. K8s 네트워크 장애의 단골 원인 (Preply 2020, loveholidays 2020 사례).

## Diagnosis
```bash
# 노드별 conntrack 사용률 확인
kubectl get --raw "/api/v1/nodes/<node>/proxy/metrics" | grep -E 'conntrack_entries|conntrack_entries_limit'

# 어떤 워크로드가 짧은 connection 다수를 만드는가
kubectl top pods -A --sort-by=memory | head -20  # 의심 후보
# 노드 진입 후:
sudo conntrack -L -n | awk '{print $5}' | cut -d= -f2 | sort | uniq -c | sort -rn | head
```

## Mitigation
1. 임시: 노드 conntrack 한도 상향
   ```bash
   sysctl -w net.netfilter.nf_conntrack_max=<2배 값>
   # 또는 kubelet --kube-reserved에 conntrack 헤드룸 반영
   ```
2. 짧은 connection 다수 만드는 클라이언트 식별 → connection pooling/keepalive 적용
3. NodeLocal DNSCache 도입 검토 — UDP DNS conntrack race 회피

## Root cause
- HTTP/1.1 keep-alive 미사용 클라이언트
- DNS UDP 폭증 (특히 Alpine `ndots:5` 이슈)
- 짧은 외부 API 호출 다수
- 노드 자체 한도가 워크로드 규모 대비 작음 (디폴트 `nf_conntrack_max`)
