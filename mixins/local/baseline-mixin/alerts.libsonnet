// Baseline alerts — kubernetes-mixin 외에 운영팀이 표준으로 켜는 알림.
// docs/baseline-alerts.md #4 (추가 베이스라인) 합의 기반.
//
// critical 5: PrometheusRuleFailures, AlertmanagerConfigInconsistent,
//             IngressControllerDown, CoreDNSDown, HighOOMKillRate
// warning 5:  CoreDNSLatencyHigh, CoreDNSErrorsHigh, HighIngress5xxRate,
//             HighDiskSaturation, HighImagePullBackOff

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
        ],
      },
    ],
  },
}
