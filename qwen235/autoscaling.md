# 基于Qwen3-235B自动扩缩容的实践

参考文档: https://kthena.volcano.sh/docs/user-guide/autoscaler

获取当前crd（qwen235-pd）中role为prefill的副本数
```shell
kubectl get modelservings.workload.serving.volcano.sh qwen235-pd -o jsonpath='{range .spec.template.roles[?(@.name=="prefill")]}{.replicas}{end}' -n vllm-project
```

## 同质目标拓展

```yaml
apiVersion: workload.serving.volcano.sh/v1alpha1
kind: AutoscalingPolicy
metadata:
  name: scaling-policy
spec:
  metrics:
  - metricName: kthena:num_requests_waiting
    targetValue: 10.0
  tolerancePercent: 10
  behavior:
    scaleUp:
      panicPolicy:
        panicThresholdPercent: 150
        panicModeHold: 5m
      stablePolicy:
        stabilizationWindow: 1m
        period: 30s
    scaleDown:
      stabilizationWindow: 5m
      period: 1m
---
apiVersion: workload.serving.volcano.sh/v1alpha1
kind: AutoscalingPolicyBinding
metadata:
  name: scaling-binding
spec:
  policyRef:
    name: scaling-policy
  homogeneousTarget:
    target:
      targetRef:
        kind: ModelServing
        name: qwen235-pd
      subTargets:
        kind: Role
        name: prefill
    minReplicas: 1
    maxReplicas: 2
```