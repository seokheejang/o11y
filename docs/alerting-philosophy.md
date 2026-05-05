# Alerting Philosophy

이 repo의 알림 룰은 다음 원칙을 따른다.

## 1. On-call이 받았을 때 할 일이 없으면, 알림은 존재하면 안 된다

— Rob Ewaschuk, *My Philosophy on Alerting* (Google SRE)

알림을 추가하기 전에 답해야 할 질문:

> "이게 새벽 3시에 울리면, 받은 사람이 무엇을 할 수 있는가?"

답이 "아무것도"이면 그 알림은 만들지 않는다. 답이 "내일 보면 됨"이면 `severity: warning`으로 Slack에만 보낸다.

## 2. 증상(symptom)에 알림, 원인(cause)에 알림 X

- ❌ CPU 80% 초과 → 사용자에게 영향 없을 수도 있음
- ❌ Pod 재시작 → 자동 회복 가능, 페이징 가치 없음
- ✅ 사용자 요청의 5xx 비율이 1% 초과
- ✅ p99 latency가 SLO를 burn 중
- ✅ RPC 노드의 블록 헤드가 10분간 정체

원인은 대시보드/로그로 진단한다. 알림은 "사용자가 아픈가?"에만 답한다.

## 3. SLO 기반 multi-window multi-burn-rate

장기 + 단기 burn rate를 동시에 보는 방식이 표준이다 (Google SRE Workbook).

- 단기 윈도우(예: 5분 burn rate ≥ 14.4): 빠른 페이징
- 장기 윈도우(예: 1시간 burn rate ≥ 6): 느린 누적 페이징

세부 임계값은 SLO와 error budget에 따라 도메인별로 결정.

## 4. 알림 수는 적게 유지한다

- 새 알림은 **인시던트가 갭을 드러냈을 때** 추가한다 — "혹시 모르니"는 금지
- 6개월 동안 한 번도 액션을 만들지 않은 알림은 삭제한다
- 노이즈 알림은 즉시 끄거나 임계값을 조정한다 — "익숙해진 알림"이 가장 위험하다

## 5. 모든 알림은 runbook을 가진다

```yaml
annotations:
  summary: "RPC 노드 블록 헤드 정체 ({{ $labels.instance }})"
  description: "지난 10분간 블록 진행 없음. peer/sync 상태 확인 필요."
  runbook_url: "https://github.com/<your-org>/<your-repo>/blob/main/docs/runbooks/<alert-name>.md"
```

`runbook_url`이 없는 critical 알림은 PR에서 막는다 (CI가 검증).

## 참고

- [My Philosophy on Alerting — Rob Ewaschuk](https://docs.google.com/document/d/199PqyG3UsyXlwieHaqbGiWVa8eMWi8zzAn0YfcApr8Q/preview)
- [Google SRE Workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- [Prometheus — Alerting Best Practices](https://prometheus.io/docs/practices/alerting/)
