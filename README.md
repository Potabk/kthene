# DeepSeek-V3.2 on Kthena + vLLM-Ascend 最佳实践文档

## 概述

本项目基于 **Kthena（Volcano Serving）** 框架，在华为昇腾（Ascend）集群上以 **Prefill-Decode（PD）分离** 架构部署 DeepSeek-V3.2-W8A8 模型，通过 **Mooncake KV Transfer** 实现高效的 KV Cache 跨节点传输，显著提升吞吐量与首 Token 延迟（TTFT）。

### 整体架构

```
客户端请求
    │
    ▼
kthena-router (LoadBalancer :80 / NodePort :31714)
    │   ModelRoute: deep-seek-V3.2 → deepseek-pd
    ▼
ModelServer (deepseek-pd)
    ├── Prefill 组（TP=8, DP=2）  ← KV Producer（Mooncake）
    │     ├── prefill-entry Pod × 1（端口 7100）
    │     └── prefill-worker Pod × 1
    └── Decode 组（TP=2, DP=8）   ← KV Consumer（Mooncake）
          ├── decode-entry Pod × 1（端口 7100）
          └── decode-worker Pod × 1
```

---

## 文件说明

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
kubectl get pods -n vllm-project -w

# 查看 ModelServing 状态
kubectl get modelserving deepseek-pd -n vllm-project

# 查看 ModelRoute 状态
kubectl get modelroute deep-seek-V3.2 -n vllm-project

# 查看路由 Service
kubectl get svc -n vllm-project
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
curl http://10.247.148.69/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ds_r1",
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
    "model": "ds_r1",
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

## 关键配置说明

### PD 分离参数设计

| 参数 | Prefill | Decode | 说明 |
|------|---------|--------|------|
| `--tensor-parallel-size` | 8 | 2 | Prefill 计算密集，用大 TP；Decode 内存带宽密集，用小 TP |
| `--data-parallel-size` | 2 | 8 | Decode 并发更高，DP 更大以支持更多并发请求 |
| `--max-num-seqs` | 8 | 40 | Prefill 每批次少序列；Decode 支持更多并发 |
| `--max-num-batched-tokens` | 16384 | 256 | Prefill 长上下文；Decode 每步只生成少量 token |
| `kv_role` | `kv_producer` | `kv_consumer` | Prefill 生产 KV，Decode 消费 KV |

### Mooncake KV Transfer 配置

```json
{
  "kv_connector": "MooncakeConnectorV1",
  "kv_port": "9000",
  "engine_id": "${GROUP_NAME}_${ROLE_ID}",
  "kv_connector_module_path": "vllm_ascend.distributed.mooncake_connector",
  "kv_connector_extra_config": {
    "use_ascend_direct": true,
    "prefill": { "dp_size": 2, "tp_size": 8 },
    "decode": { "dp_size": 8, "tp_size": 2 }
  }
}
```

- `engine_id` 由 `GROUP_NAME`（ServingGroup 名称）和 `ROLE_ID` 共同唯一标识，确保 Prefill 与 Decode 实例能正确配对
- `use_ascend_direct: true` 启用昇腾 RDMA 直传，避免 KV Cache 经过 CPU 内存中转，大幅降低延迟
- KV 传输端口（9000）与推理服务端口（7100）独立，互不干扰

### 推测解码（Speculative Decoding）

```json
{"num_speculative_tokens": 1, "method": "deepseek_mtp"}
```

使用 DeepSeek MTP（Multi-Token Prediction）方法，每步推测 1 个 token，对 Decode 阶段加速效果显著，建议保持开启。

### Decode 专项优化

```json
{"cudagraph_mode": "FULL_DECODE_ONLY"}
```

仅对 Decode 阶段启用完整 CUDA Graph 优化，减少 kernel launch 开销，降低单 token 延迟。

---

## 资源规划

### 当前配置（每个 Role 单副本）

| 角色 | Pod 数 | Ascend-1980 卡数 | 内存 | CPU |
|------|--------|-----------------|------|-----|
| prefill-entry | 1 | 16 | 512Gi | 125 |
| prefill-worker | 1 | 16 | 512Gi | 125 |
| decode-entry | 1 | 16 | 512Gi | 125 |
| decode-worker | 1 | 16 | 512Gi | 125 |
| **合计** | **4** | **64** | **2Ti** | **500** |

### 扩容建议

**提升并发吞吐**：增加 `spec.replicas`（ServingGroup 级扩容），整组 Prefill+Decode 同步扩展：

```yaml
# model_server.yaml
spec:
  replicas: 2  # 从 1 改为 2，整体资源翻倍
```

**调整 Decode 比例**：若 Decode 成为瓶颈，单独扩 Decode role 副本数：

```yaml
roles:
- name: decode
  replicas: 2  # 独立扩 decode 副本
  workerReplicas: 1
```

---

## 故障排查

### Pod 长时间 Pending

```bash
# 查看调度事件
kubectl describe pod <pod-name> -n vllm-project | grep -A 20 Events

# 检查 Ascend 资源是否充足
kubectl describe nodes | grep -A 5 "huawei.com/ascend-1980"
```

常见原因：Ascend 卡资源不足；PVC 未绑定；节点亲和性不满足。

### Prefill/Decode 无法建立 KV 连接

```bash
# 检查 entry 服务是否解析正常
kubectl exec -it <decode-worker-pod> -n vllm-project -- \
  getent hosts deepseek-pd-prefill-entry.vllm-project.svc.cluster.local

# 查看 Mooncake 连接日志
kubectl logs <prefill-entry-pod> -n vllm-project | grep -i mooncake
kubectl logs <decode-entry-pod> -n vllm-project | grep -i mooncake
```

常见原因：`MOONCAKE_ENGINE_ID` 不匹配（确认 `GROUP_NAME` 和 `ROLE_ID` 环境变量注入正确）；KV 端口 9000 被防火墙拦截。

### 推理请求返回 404 / 503

```bash
# 确认 ModelRoute 路由规则生效
kubectl describe modelroute deep-seek-r1 -n vllm-project

# 确认 ModelServer 后端 Pod 就绪
kubectl get modelserver deepseek-pd -n vllm-project
kubectl get pods -n vllm-project -l modelserving.volcano.sh/name=deepseek-pd
```

### 开启健康探针（当前已注释）

生产环境建议取消 `model_server.yaml` 中探针的注释，防止未就绪的 Pod 接收流量：

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 7100
  initialDelaySeconds: 60
  periodSeconds: 10
  failureThreshold: 180   # 最长等待 30 分钟启动
readinessProbe:
  httpGet:
    path: /health
    port: 7100
  periodSeconds: 10
  failureThreshold: 3
```

---

## 生产环境注意事项

1. **网卡名称**：`config.yaml` 中 `nic_name="enp23s0f3"` 必须与实际节点网卡名一致，否则 HCCL 通信失败。部署前执行 `ip link` 确认。

2. **镜像版本**：当前使用 `vllm-ascend:nightly-a3`（nightly 构建），生产环境建议固定到具体版本标签，避免滚动更新引入不稳定版本。

3. **recoveryPolicy**：`ServingGroupRecreate` 表示任意 Pod 失败时重建整个 ServingGroup，保证 PD 配对一致性。不要改为 `Never`，否则 Prefill/Decode 不匹配会导致 KV 传输失败。

4. **模型缓存**：PVC `nv-action-vllm-benchmarks-v2` 挂载到 `/root/.cache`，确保模型权重已预先下载到 PVC，避免启动时从网络拉取（`VLLM_USE_MODELSCOPE=true` 会从 ModelScope 拉取）。

5. **启动超时**：`VLLM_ENGINE_READY_TIMEOUT_S=1800` 设置了 30 分钟启动超时，大模型首次加载时间较长，此值不建议缩短。

6. **prefix caching**：当前配置 `--no-enable-prefix-caching`，禁用了 prefix cache。如果业务有大量重复前缀（如 system prompt），可评估开启以提升命中率。
