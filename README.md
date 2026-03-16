# DeepSeek-V3.2 on Kthena + vLLM-Ascend 最佳实践文档

## 概述

本项目基于 **[Kthena(Volcano Serving)](https://kthena.volcano.sh/docs/intro)** 框架，在华为昇腾（Ascend）集群上以 **Prefill-Decode（PD）分离** 架构部署 DeepSeek-V3.2-W8A8 模型，通过 **Mooncake KV Transfer** 实现高效的 KV Cache 跨节点传输，显著提升吞吐量与首 Token 延迟（TTFT）。

### 整体架构

```
客户端请求
    │
    ▼
kthena-router (LoadBalancer :80 / NodePort :31714)
    │   ModelRoute: deepseek-V3.2 → deepseek-pd
    ▼
ModelServer (deepseek-pd)
    ├── Prefill 组（TP=16, DP=2）  ← KV Producer（Mooncake）
    │     ├── prefill-entry Pod × 1（端口 7100）
    │     └── prefill-worker Pod × 1
    └── Decode 组（TP=4, DP=8）   ← KV Consumer（Mooncake）
          ├── decode-entry Pod × 1（端口 7100）
          └── decode-worker Pod × 1
```

---

## 文件说明

以deepseek-v3.2为例:

| 文件 | 作用 |
|------|------|
| `config.yaml` | ConfigMap，存放 prefill/decode 启动脚本 |
| `model_server.yaml` | ModelServing CRD，定义 Pod 拓扑、资源、调度 |
| `router.yaml` | ModelRoute + ModelServer，定义路由规则 |

---

## 部署步骤

### 1. 前置条件

- Kubernetes 集群已安装 Volcano 调度器
- 已安装 Kthena（Volcano Serving）CRD 和 Controller
- 节点已安装昇腾驱动，资源名称为 `huawei.com/ascend-1980`
- PVC `nv-action-vllm-benchmarks-v2` 已创建并挂载模型权重
- 网卡名称与实际环境一致（当前配置为 `enp23s0f3`）

### 2. 部署顺序

按以下顺序依次 apply，避免资源依赖问题：

```bash
# Step 1: 创建启动脚本 ConfigMap
kubectl apply -f config.yaml -n vllm-project

# Step 2: 创建 ModelServing 工作负载（包含 Headless Service）
kubectl apply -f model_server.yaml -n vllm-project

# Step 3: 创建 ModelServer 和 ModelRoute（路由层）
kubectl apply -f router.yaml -n vllm-project
```

### 3. 验证部署状态

```bash
# 查看 Pod 状态（等待所有 Pod Running）
kubectl get pods -n vllm-project | grep '^deepseek'
deepseek-pd-0-decode-0-0                         1/1     Running   0          122m
deepseek-pd-0-decode-0-1                         1/1     Running   0          122m
deepseek-pd-0-prefill-0-0                        1/1     Running   0          122m
deepseek-pd-0-prefill-0-1                        1/1     Running   0          122m

# 查看 ModelServing 状态
kubectl get modelserving deepseek-pd -n vllm-project
NAME          AGE
deepseek-pd   120m

# 查看 ModelRoute 状态
kubectl get modelroute deepseek-v32 -n vllm-project
NAME           AGE
deepseek-v32   107m

# 查看路由 Service
kubectl get svc -n vllm-project
NAME                                TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
deepseek-pd-0-decode-0-0            ClusterIP      None             <none>        <none>         124m
deepseek-pd-0-prefill-0-0           ClusterIP      None             <none>        <none>         124m
deepseek-pd-decode-entry            ClusterIP      None             <none>        12321/TCP      124m
deepseek-pd-prefill-entry           ClusterIP      None             <none>        12321/TCP      124m
kthena-controller-manager-webhook   ClusterIP      10.247.187.177   <none>        443/TCP        4d3h
kthena-router                       LoadBalancer   10.247.148.69    <pending>     80:31714/TCP   4d3h
kthena-router-webhook               ClusterIP      10.247.109.13    <none>        443/TCP        4d3h
```

正常状态下应有 4 个业务 Pod：

```
deepseek-pd-0-prefill-*-0-0   Running   # prefill entry
deepseek-pd-0-prefill-*-0-1   Running   # prefill worker
deepseek-pd-0-decode-*-0-0    Running   # decode entry
deepseek-pd-0-decode-*-0-1    Running   # decode worker
```

---

## 访问服务

### 集群内访问（推荐）

通过 `kthena-router` ClusterIP 访问，端口 80：

```bash
curl http://kthene-router/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ds-v32",
    "messages": [{"role": "user", "content": "你好，请介绍一下自己"}],
    "max_tokens": 512,
    "temperature": 0.7
  }'
```

### 集群外访问

使用 NodePort 31714，替换为任意节点 IP：

```bash
# 获取节点 IP
kubectl get nodes -o wide

curl http://<NODE_IP>:31714/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ds-v32",
    "messages": [{"role": "user", "content": "你好"}],
    "max_tokens": 512
  }'
```

### 健康检查

```bash
# 查询已加载的模型
curl http://10.247.148.69/v1/models

# 也可直接访问某个 entry Pod 的健康接口（需 port-forward）
kubectl port-forward pod/<prefill-entry-pod> 7100:7100 -n vllm-project
curl http://localhost:7100/health
```

---

## 服务启动参数配置

参考vllm-ascend [DeepSeek-V3.2](https://docs.vllm.ai/projects/ascend/en/latest/tutorials/models/DeepSeek-V3.2.html) 官方教程

**请注意**: 本教程使用vllm-ascend镜像版本为quay.io/ascend/vllm-ascend:v0.15.0rc1-a3

## 资源规划

### 当前配置（每个 Role 单副本）

| 角色 | Pod 数 | Ascend-1980 卡数 | 内存 | CPU |
|------|--------|-----------------|------|-----|
| prefill-entry | 1 | 16 | 512Gi | 125 |
| prefill-worker | 1 | 16 | 512Gi | 125 |
| decode-entry | 1 | 16 | 512Gi | 125 |
| decode-worker | 1 | 16 | 512Gi | 125 |
| **合计** | **4** | **64** | **2Ti** | **500** |


---

## Benchmark

```shell
vllm bench serve \
  --base-url http://kthena-router \
  --model /root/.cache/modelscope/hub/models/vllm-ascend/DeepSeek-V3___2-W8A8 \
  --served-model-name ds-v32 \
  --endpoint /v1/completions \
  --dataset-name random \
  --random-input 2048 \
  --random-output 1024 \
  --request-rate 10 \
  --num-prompt 100


# round 1
============ Serving Benchmark Result ============
Successful requests:                     55
Failed requests:                         45
Request rate configured (RPS):           10.00
Benchmark duration (s):                  117.78
Total input tokens:                      112640
Total generated tokens:                  56320
Request throughput (req/s):              0.47
Output token throughput (tok/s):         478.16
Peak output token throughput (tok/s):    896.00
Peak concurrent requests:                55.00
Total token throughput (tok/s):          1434.49
---------------Time to First Token----------------
Mean TTFT (ms):                          37612.83
Median TTFT (ms):                        38434.61
P99 TTFT (ms):                           43065.34
-----Time per Output Token (excl. 1st token)------
Mean TPOT (ms):                          57.28
Median TPOT (ms):                        53.15
P99 TPOT (ms):                           95.47
---------------Inter-token Latency----------------
Mean ITL (ms):                           76.76
Median ITL (ms):                         0.00
P99 ITL (ms):                            1370.84
==================================================

# round 2
============ Serving Benchmark Result ============
Successful requests:                     58
Failed requests:                         42
Request rate configured (RPS):           10.00
Benchmark duration (s):                  89.44
Total input tokens:                      118784
Total generated tokens:                  59392
Request throughput (req/s):              0.65
Output token throughput (tok/s):         664.04
Peak output token throughput (tok/s):    888.00
Peak concurrent requests:                58.00
Total token throughput (tok/s):          1992.13
---------------Time to First Token----------------
Mean TTFT (ms):                          5116.85
Median TTFT (ms):                        5120.14
P99 TTFT (ms):                           8834.76
-----Time per Output Token (excl. 1st token)------
Mean TPOT (ms):                          56.85
Median TPOT (ms):                        51.43
P99 TPOT (ms):                           71.89
---------------Inter-token Latency----------------
Mean ITL (ms):                           73.78
Median ITL (ms):                         0.00
P99 ITL (ms):                            1350.82
==================================================

# round 3
============ Serving Benchmark Result ============
Successful requests:                     62
Failed requests:                         38
Request rate configured (RPS):           10.00
Benchmark duration (s):                  87.71
Total input tokens:                      126976
Total generated tokens:                  63488
Request throughput (req/s):              0.71
Output token throughput (tok/s):         723.88
Peak output token throughput (tok/s):    1264.00
Peak concurrent requests:                62.00
Total token throughput (tok/s):          2171.63
---------------Time to First Token----------------
Mean TTFT (ms):                          5076.98
Median TTFT (ms):                        5438.99
P99 TTFT (ms):                           8075.20
-----Time per Output Token (excl. 1st token)------
Mean TPOT (ms):                          54.51
Median TPOT (ms):                        52.55
P99 TPOT (ms):                           70.57
---------------Inter-token Latency----------------
Mean ITL (ms):                           71.73
Median ITL (ms):                         0.00
P99 ITL (ms):                            1227.06
==================================================

```