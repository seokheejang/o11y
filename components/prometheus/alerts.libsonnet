// Baseline alerts — kubernetes-mixin 외에 운영팀이 표준으로 켜는 알림.
// docs/baseline-alerts.md #4 (추가 베이스라인) + workload-network 보강 합의 기반.
//
// critical 6: PrometheusRuleFailures, AlertmanagerConfigInconsistent,
//             IngressControllerDown, CoreDNSDown, HighOOMKillRate,
//             NodeConntrackNearLimit
// warning 11: CoreDNSLatencyHigh, CoreDNSErrorsHigh, HighIngress5xxRate,
//             HighIngress4xxRate, HighDiskSaturation, HighImagePullBackOff,
//             PodRestartingTooOften, WorkloadRolloutStuck, JobFailedNonCron,
//             ServiceEndpointsEmpty, NodeNetworkErrorsHigh

{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'baseline-meta',
        rules: [
          {
            alert: 'PrometheusRuleFailures',
            expr: 'increase(prometheus_rule_evaluation_failures_total[5m]) > 0',
            'for': '5m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'Prometheus rule evaluation failing — alerting itself is degraded.',
              description: '{{ $labels.instance }} has rule eval failures in the last 5m. Other alerts may not fire.',
              runbook_url: $._config.runbookBase + '/PrometheusRuleFailures.md',
            },
          },
          {
            alert: 'AlertmanagerConfigInconsistent',
            expr: |||
              count by (service, cluster) (
                count_values by (service, cluster) ("config_hash", alertmanager_config_hash{%(alertmanagerSelector)s})
              ) > 1
            ||| % $._config,
            'for': '10m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'Alertmanager HA replicas have divergent configs.',
              description: 'Alertmanager service {{ $labels.service }} has inconsistent config across replicas. Risk of duplicate or missed notifications.',
              runbook_url: $._config.runbookBase + '/AlertmanagerConfigInconsistent.md',
            },
          },
        ],
      },
      {
        name: 'baseline-network',
        rules: [
          {
            alert: 'IngressControllerDown',
            expr: 'absent(up{%(ingressControllerSelector)s} == 1)' % $._config,
            'for': '5m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'Ingress controller is down — north-south traffic blocked.',
              description: 'No ingress controller targets are up. All external traffic via this controller fails.',
              runbook_url: $._config.runbookBase + '/IngressControllerDown.md',
            },
          },
          {
            alert: 'HighIngress5xxRate',
            expr: |||
              sum by (ingress, namespace) (rate(nginx_ingress_controller_requests{status=~"5.."}[5m]))
                /
              sum by (ingress, namespace) (rate(nginx_ingress_controller_requests[5m]))
                > %(ingress5xxRatio)s
            ||| % $._config.thresholds,
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Ingress {{ $labels.namespace }}/{{ $labels.ingress }} 5xx ratio > 5%.',
              description: '5xx ratio is {{ $value | humanizePercentage }} for the last 10m.',
            },
          },
          {
            // 4xx 급증은 outage가 아니므로 warning. 단 배포 직후 인증/route 깨짐의 강력한 신호.
            // 최소 트래픽 요건(1 req/s)으로 저트래픽 false positive 차단.
            alert: 'HighIngress4xxRate',
            expr: |||
              sum by (ingress, namespace) (rate(nginx_ingress_controller_requests{status=~"4.."}[5m]))
                /
              sum by (ingress, namespace) (rate(nginx_ingress_controller_requests[5m]))
                > %(ingress4xxRatio)s
              and
              sum by (ingress, namespace) (rate(nginx_ingress_controller_requests[5m]))
                > %(ingress4xxMinReqPerSec)s
            ||| % $._config.thresholds,
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Ingress {{ $labels.namespace }}/{{ $labels.ingress }} 4xx ratio > 5%.',
              description: '4xx ratio is {{ $value | humanizePercentage }} for the last 10m. Often indicates auth/route misconfig after deploy.',
            },
          },
        ],
      },
      {
        name: 'baseline-dns',
        rules: [
          {
            alert: 'CoreDNSDown',
            expr: 'absent(up{%(corednsSelector)s} == 1)' % $._config,
            'for': '5m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'CoreDNS is down — service discovery broken.',
              description: 'CoreDNS targets absent for 5m. All in-cluster DNS resolution affected.',
              runbook_url: $._config.runbookBase + '/CoreDNSDown.md',
            },
          },
          {
            alert: 'CoreDNSLatencyHigh',
            expr: |||
              histogram_quantile(0.99, sum by (le) (rate(coredns_dns_request_duration_seconds_bucket[5m])))
                > %(coreDNSp99LatencySeconds)s
            ||| % $._config.thresholds,
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'CoreDNS p99 latency > 1s.',
              description: 'p99 latency is {{ $value }}s for the last 10m.',
            },
          },
          {
            alert: 'CoreDNSErrorsHigh',
            expr: |||
              sum(rate(coredns_dns_responses_total{rcode=~"SERVFAIL|REFUSED"}[5m]))
                /
              sum(rate(coredns_dns_responses_total[5m]))
                > %(coreDNSErrorRatio)s
            ||| % $._config.thresholds,
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'CoreDNS SERVFAIL/REFUSED ratio > 5%.',
              description: 'Error ratio is {{ $value | humanizePercentage }} for the last 10m.',
            },
          },
        ],
      },
      {
        name: 'baseline-workload',
        rules: [
          {
            alert: 'HighOOMKillRate',
            expr: 'sum(increase(container_oom_events_total[5m])) > %(oomKillRate5m)s' % $._config.thresholds,
            'for': '5m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'High OOMKill rate cluster-wide.',
              description: '{{ $value }} OOMKills in the last 5m. Indicates memory pressure or limit misconfiguration.',
              runbook_url: $._config.runbookBase + '/HighOOMKillRate.md',
            },
          },
          {
            alert: 'HighImagePullBackOff',
            expr: |||
              sum by (namespace, pod) (
                max_over_time(kube_pod_container_status_waiting_reason{reason="ImagePullBackOff", %(kubeStateMetricsSelector)s}[15m])
              ) > 0
            ||| % $._config,
            'for': '15m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Pod {{ $labels.namespace }}/{{ $labels.pod }} stuck in ImagePullBackOff.',
              description: 'Image pull failing for 15m. Check registry credentials or image tag.',
            },
          },
          {
            alert: 'HighDiskSaturation',
            expr: 'rate(node_disk_io_time_seconds_total[5m]) > %(diskSaturationRatio)s' % $._config.thresholds,
            'for': '15m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Disk {{ $labels.device }} on {{ $labels.instance }} > 90% saturated.',
              description: 'I/O time ratio is {{ $value | humanizePercentage }} for the last 15m.',
            },
          },
          {
            // CrashLoopBackOff 진입 전 단계 포착. KubePodCrashLooping은 횟수 임계 없음 — 보완 신호.
            alert: 'PodRestartingTooOften',
            expr: |||
              increase(kube_pod_container_status_restarts_total{%(kubeStateMetricsSelector)s}[1h])
                > %(podRestart1h)s
            ||| % ($._config + $._config.thresholds),
            'for': '15m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Pod {{ $labels.namespace }}/{{ $labels.pod }} restarted > 5 times in last 1h.',
              description: 'Container {{ $labels.container }} restarting repeatedly. Investigate before it CrashLoops.',
            },
          },
          {
            // 잘못된 이미지로 배포 후 까먹음 시나리오의 직접 신호.
            // KubeDeploymentReplicasMismatch는 시간 기반 아님 — 진행 정체를 잡는 보완 신호.
            alert: 'WorkloadRolloutStuck',
            expr: |||
              kube_deployment_status_observed_generation{%(kubeStateMetricsSelector)s}
                != kube_deployment_metadata_generation{%(kubeStateMetricsSelector)s}
              or
              (
                kube_deployment_spec_replicas{%(kubeStateMetricsSelector)s}
                  != kube_deployment_status_replicas_available{%(kubeStateMetricsSelector)s}
              )
            ||| % $._config,
            'for': '30m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Deployment {{ $labels.namespace }}/{{ $labels.deployment }} rollout stuck > 30m.',
              description: 'Generation mismatch or replicas-available shortfall persisted for 30m. Likely failed rollout.',
            },
          },
          {
            // CronJob 자식이 아닌 1회성 Job 실패만 — KubeJobFailed disable의 빈자리 메움.
            alert: 'JobFailedNonCron',
            expr: |||
              kube_job_status_failed{%(kubeStateMetricsSelector)s} > 0
              unless on (job_name, namespace)
              kube_job_owner{%(kubeStateMetricsSelector)s, owner_kind="CronJob"}
            ||| % $._config,
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Job {{ $labels.namespace }}/{{ $labels.job_name }} failed (non-cron).',
              description: 'A non-cron Job has failed. CronJob retry noise is excluded by owner_kind filter.',
            },
          },
          {
            // selector 오타, Pod 없음, readiness 모두 실패 — 통합 신호.
            // 시스템 ns(kube-system 등) 제외로 false positive 차단.
            alert: 'ServiceEndpointsEmpty',
            expr: |||
              kube_endpoint_address_available{%(kubeStateMetricsSelector)s, namespace!~"kube-system|kube-public|kube-node-lease"} == 0
            ||| % $._config,
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Service {{ $labels.namespace }}/{{ $labels.endpoint }} has 0 endpoints.',
              description: 'No ready endpoints for 10m. Selector mismatch, no pods, or readiness all failing.',
            },
          },
        ],
      },
      {
        name: 'baseline-node',
        rules: [
          {
            // conntrack 고갈은 K8s 네트워크 장애의 단골 원인 (Preply, loveholidays).
            // 80%부터 critical로 받아 사전 조치 시간 확보.
            alert: 'NodeConntrackNearLimit',
            expr: |||
              node_nf_conntrack_entries{%(nodeExporterSelector)s}
                /
              node_nf_conntrack_entries_limit{%(nodeExporterSelector)s}
                > %(conntrackUsageRatio)s
            ||| % ($._config + $._config.thresholds),
            'for': '10m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'Node {{ $labels.instance }} conntrack table > 80% full.',
              description: 'Conntrack usage at {{ $value | humanizePercentage }}. Risk of new connection drops.',
              runbook_url: $._config.runbookBase + '/NodeConntrackNearLimit.md',
            },
          },
          {
            // NIC 에러/드롭 — 드라이버/하드웨어/스위치 이슈 통합.
            alert: 'NodeNetworkErrorsHigh',
            expr: |||
              rate(node_network_receive_errs_total{%(nodeExporterSelector)s}[5m])
                + rate(node_network_receive_drop_total{%(nodeExporterSelector)s}[5m])
                + rate(node_network_transmit_errs_total{%(nodeExporterSelector)s}[5m])
                + rate(node_network_transmit_drop_total{%(nodeExporterSelector)s}[5m])
                > %(nodeNetErrorRate)s
            ||| % ($._config + $._config.thresholds),
            'for': '15m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Node {{ $labels.instance }} network errors/drops on {{ $labels.device }} > 0.01/s.',
              description: 'Sustained NIC errors or drops for 15m. Check driver, hardware, or upstream switch.',
            },
          },
        ],
      },
    ],
  },
}
