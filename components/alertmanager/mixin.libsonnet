// Alertmanager 컴포넌트 진입점.
//
// routing intent(라우팅 트리 + receivers + inhibit_rules)를 `alertmanagerConfig+::`로
// export 한다.
//   - routing.libsonnet → `alertmanagerConfig.{route, receivers, inhibitRules}`
//
// CR ↔ raw alertmanager.yml 변환 헬퍼는 components/_lib/alertmanager.libsonnet.

(import 'routing.libsonnet')
