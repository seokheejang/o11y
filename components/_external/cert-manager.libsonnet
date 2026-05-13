// cert-manager mixin import wrap (stub).
//
// 디폴트로 미활성화. 활성화 절차:
//   1) jsonnetfile.json에 의존성 추가:
//        jb install github.com/imusmanmalik/cert-manager-mixin@master
//
//   2) mixins/main.libsonnet에서 certManagerEnabled = true로 변경.
//      그러면 main이 이 파일을 import하여 prometheusAlerts.groups를 합성한다.
//
//   3) make build && make test 통과 확인.
//
// 이 파일이 분리되어 있는 이유:
//   - cert-manager 환경이 아닌 fork에서는 vendor에 cert-manager-mixin이 없으므로
//     main이 conditional import로만 이 파일을 가리킨다 (`if certManagerEnabled then ...`).
//   - 활성화 시 selector override / 임계값 조정도 이 파일에 추가한다.

(import 'github.com/imusmanmalik/cert-manager-mixin/mixin.libsonnet') +
{
  _config+:: {
    // 운영 환경 selector에 맞게 override
    certManagerSelector: 'job="cert-manager"',
  },
}
