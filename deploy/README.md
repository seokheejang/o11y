# deploy/

이 monorepo를 fork(코드 복사)한 운영자가 **환경에 실제로 배포할 때 필요한 자원**의 진입점.

```
deploy/
├── envs/
│   ├── _base/                       — 환경 공통 chart values + Alertmanager CR patch
│   ├── example-dev/                 — 카피용 placeholder 환경 (REPLACE_* 토큰)
│   │   ├── values.yaml              — env-specific chart override
│   │   ├── app-of-apps.yaml         — env root Application (참조용)
│   │   └── apps/                    — child Applications (chart + 자체 mixin)
│   └── ...                          — 운영자가 example-dev 카피해서 생성
├── secrets/
│   ├── sealed/                      — SealedSecrets 패턴
│   ├── eso/                         — External Secrets Operator 패턴 (운영 표준)
│   └── scripts/                     — envsubst 기반 빠른 검증 스크립트
└── argocd/
    └── appset-o11y.yaml             — ApplicationSet (모든 env 자동 generate)
```

## 사용 모델 (간단 흐름)

```
1) fork 받기 (코드 복사로 별도 repo)
2) deploy/envs/example-dev 카피 → 자기 env 디렉토리 만들기 (예: dev-a, staging, prod-a)
3) REPLACE_* 토큰 치환 (cluster name, repo URL, ArgoCD cluster URL)
4) deploy/secrets에서 패턴 선택 (sealed / eso) + Secret 생성
5) deploy/argocd/appset-o11y.yaml의 elements에 env 추가 + ArgoCD에 1회 apply
6) ArgoCD가 env별 stack을 자동 sync
```

각 디렉토리 README에 상세 절차.

## 디자인 결정

- **`overlays/` 명명 X** — Kustomize 관습이라 jsonnet 기반 본 repo와 안 맞음.
- **envs 디렉토리에 ArgoCD 객체 같이** — App-of-Apps per env 패턴. envs는 단순 values 모음이 아니라 "env 단위 운영 묶음".
- **example-* placeholder** — 1개만 둠 (`example-dev`). prod 사례는 운영자가 카피 후 chart 버전/replica/retention 조정으로 만들면 됨 — repo 안에서 인위적 사례 다수화 회피.
- **SealedSecrets + ESO 둘 다** — 환경 인프라마다 backend 운영 여부가 달라 한쪽 강제 X. README에서 선택 가이드.
- **chart 정합 강제 X** — e2e가 OSS 최신(85.0.2), prod는 더 보수적 선택 가능. chart 버전은 env별 자유.

자세한 fork 절차는 [docs/deploying.md](../docs/deploying.md) (PR-3에서 추가).
