# Runbooks

알림이 fire 됐을 때 on-call이 따라가는 절차서. 알림의 `runbook_url` annotation이 가리키는 곳.

## 룬북 작성 규칙

각 룬북은 다음 섹션을 포함한다:

1. **Symptom** — 어떤 알림이 어떤 조건에서 울리는가
2. **Impact** — 사용자/서비스에 어떤 영향이 있는가
3. **Diagnosis** — 1~3분 안에 원인을 좁히는 명령/대시보드 링크
4. **Mitigation** — 즉시 조치 (대증 요법)
5. **Root cause / Postmortem** — 영구 해결로 이어지는 다음 단계

## 룬북 인덱스

다음 PR부터 자체 mixin이 추가되면 해당 알림별 룬북이 여기 채워진다.

자체 mixin이 추가되는 PR마다 이 인덱스도 업데이트한다.

## 템플릿

새 룬북을 만들 때는 다음 템플릿을 복사:

````markdown
# <AlertName>

## Symptom
- Alert: `<AlertName>`
- Severity: `critical` / `warning`
- Trigger: <조건>

## Impact
<사용자/서비스 영향>

## Diagnosis
- Dashboard: [<링크>]
- Logs: `<쿼리>`
- 명령:
  ```bash
  kubectl ...
  ```

## Mitigation
1. ...
2. ...

## Root cause
<원인이 자주 어떤 것이었는지, 영구 해결 방향>
````
