kind: ConfigMap
apiVersion: v1
metadata:
  name: deepseek-pd-cm
data:
  prefill.sh: |
    nic_name="enp23s0f3"  # network card name
    local_ip=$POD_IP
    export HCCL_IF_IP=$local_ip
    export GLOO_SOCKET_IFNAME=$nic_name
    export TP_SOCKET_IFNAME=$nic_name
    export HCCL_SOCKET_IFNAME=$nic_name
    export OMP_PROC_BIND=false
    export OMP_NUM_THREADS=10
    export HCCL_BUFFSIZE=256
    export TASK_QUEUE_ENABLE=1
    export HCCL_OP_EXPANSION_MODE="AIV"
    export MOONCAKE_ENGINE_ID="${GROUP_NAME}_${ROLE_ID}"
    export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
    export VLLM_ENGINE_READY_TIMEOUT_S=1800
    vllm serve Qwen/Qwen3-30B-A3B \
      --host $POD_IP \
      --port "7100" \
      --data-parallel-size 2 \
      --data-parallel-start-rank 0 \
      --data-parallel-size-local 1 \
      --data-parallel-address $POD_IP \
      --data-parallel-rpc-port 12321 \
      --tensor-parallel-size 8 \
      --enable-expert-parallel \
      --seed 1024 \
      --served-model-name ds_r1 \
      --kv-transfer-config \
      '{"kv_connector": "MooncakeConnectorV1",
      "kv_role": "kv_producer",
      "kv_port": "9000",
      "engine_id": "$MOONCAKE_ENGINE_ID",
      "kv_connector_module_path": "vllm_ascend.distributed.mooncake_connector",
      "kv_connector_extra_config": {
                "use_ascend_direct": true,
                "prefill": {
                        "dp_size": 2,
                        "tp_size": 8
                },
                "decode": {
                        "dp_size": 8,
                        "tp_size": 2
                }
          }
      }'
  prefill-worker.sh: |
    until MASTER_IP=$(getent hosts deepseek-pd-prefill-entry.vllm-project.svc.cluster.local 2>/dev/null | awk '{print $1}') && [ -n "$MASTER_IP" ]; do
      echo "Waiting for prefill entry pod..."
      sleep 5
    done
    echo "Prefill entry IP: $MASTER_IP"
    nic_name="enp23s0f3"  # network card name
    local_ip=$POD_IP
    export HCCL_IF_IP=$local_ip
    export GLOO_SOCKET_IFNAME=$nic_name
    export TP_SOCKET_IFNAME=$nic_name
    export HCCL_SOCKET_IFNAME=$nic_name
    export OMP_PROC_BIND=false
    export OMP_NUM_THREADS=10
    export HCCL_BUFFSIZE=256
    export TASK_QUEUE_ENABLE=1
    export HCCL_OP_EXPANSION_MODE="AIV"
    export MOONCAKE_ENGINE_ID="${GROUP_NAME}_${ROLE_ID}"
    export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
    export VLLM_ENGINE_READY_TIMEOUT_S=1800
    vllm serve Qwen/Qwen3-30B-A3B \
      --host $POD_IP \
      --port "7100" \
      --headless \
      --data-parallel-size 2 \
      --data-parallel-start-rank 1 \
      --data-parallel-size-local 1 \
      --data-parallel-address $MASTER_IP \
      --data-parallel-rpc-port 12321 \
      --tensor-parallel-size 8 \
      --enable-expert-parallel \
      --seed 1024 \
      --served-model-name ds_r1 \
      --kv-transfer-config \
      '{"kv_connector": "MooncakeConnectorV1",
      "kv_role": "kv_producer",
      "kv_port": "9000",
      "engine_id": "$MOONCAKE_ENGINE_ID",
      "kv_connector_module_path": "vllm_ascend.distributed.mooncake_connector",
      "kv_connector_extra_config": {
                "use_ascend_direct": true,
                "prefill": {
                        "dp_size": 2,
                        "tp_size": 8
                },
                "decode": {
                        "dp_size": 8,
                        "tp_size": 2
                }
          }
      }'
  decode.sh: |
    nic_name="enp23s0f3"  # network card name
    local_ip=$POD_IP
    export HCCL_IF_IP=$local_ip
    export GLOO_SOCKET_IFNAME=$nic_name
    export TP_SOCKET_IFNAME=$nic_name
    export HCCL_SOCKET_IFNAME=$nic_name
    export OMP_PROC_BIND=false
    export OMP_NUM_THREADS=10
    export VLLM_ASCEND_ENABLE_MLAPO=1
    export HCCL_BUFFSIZE=600
    export TASK_QUEUE_ENABLE=1
    export HCCL_OP_EXPANSION_MODE="AIV"
    export MOONCAKE_ENGINE_ID="${GROUP_NAME}_${ROLE_ID}"
    export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
    export VLLM_ENGINE_READY_TIMEOUT_S=1800
    vllm serve Qwen/Qwen3-30B-A3B \
      --host $POD_IP \
      --port "7100" \
      --data-parallel-size 8 \
      --data-parallel-start-rank 0 \
      --data-parallel-size-local 4 \
      --data-parallel-address $POD_IP \
      --data-parallel-rpc-port 12321 \
      --tensor-parallel-size 2 \
      --enable-expert-parallel \
      --seed 1024 \
      --served-model-name ds_r1 \
      --max-model-len 40000 \
      --max-num-batched-tokens 256 \
      --no-enable-prefix-caching \
      --max-num-seqs 40 \
      --trust-remote-code \
      --compilation-config '{"cudagraph_mode": "FULL_DECODE_ONLY"}' \
      --kv-transfer-config \
      '{"kv_connector": "MooncakeConnectorV1",
      "kv_role": "kv_consumer",
      "kv_port": "9000",
      "engine_id": "$MOONCAKE_ENGINE_ID",
      "kv_connector_module_path": "vllm_ascend.distributed.mooncake_connector",
      "kv_connector_extra_config": {
                "use_ascend_direct": true,
                "prefill": {
                        "dp_size": 2,
                        "tp_size": 8
                },
                "decode": {
                        "dp_size": 8,
                        "tp_size": 2
                }
          }
      }'
  decode-worker.sh: |
    until MASTER_IP=$(getent hosts deepseek-pd-decode-entry.vllm-project.svc.cluster.local 2>/dev/null | awk '{print $1}') && [ -n "$MASTER_IP" ]; do
      echo "Waiting for decode entry pod..."
      sleep 5
    done
    echo "Decode entry IP: $MASTER_IP"
    nic_name="enp23s0f3"  # network card name
    local_ip=$POD_IP
    export HCCL_IF_IP=$local_ip
    export GLOO_SOCKET_IFNAME=$nic_name
    export TP_SOCKET_IFNAME=$nic_name
    export HCCL_SOCKET_IFNAME=$nic_name
    export OMP_PROC_BIND=false
    export OMP_NUM_THREADS=10
    export VLLM_ASCEND_ENABLE_MLAPO=1
    export HCCL_BUFFSIZE=600
    export TASK_QUEUE_ENABLE=1
    export HCCL_OP_EXPANSION_MODE="AIV"
    export MOONCAKE_ENGINE_ID="${GROUP_NAME}_${ROLE_ID}"
    export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
    export VLLM_ENGINE_READY_TIMEOUT_S=1800
    vllm serve Qwen/Qwen3-30B-A3B \
      --host $POD_IP \
      --port "7100" \
      --headless \
      --data-parallel-size 8 \
      --data-parallel-start-rank 4 \
      --data-parallel-size-local 4 \
      --data-parallel-address $MASTER_IP \
      --data-parallel-rpc-port 12321 \
      --tensor-parallel-size 2 \
      --enable-expert-parallel \
      --seed 1024 \
      --served-model-name ds_r1 \
      --max-model-len 40000 \
      --max-num-batched-tokens 256 \
      --max-num-seqs 40 \
      --trust-remote-code \
      --gpu-memory-utilization 0.94  \
      --no-enable-prefix-caching \
      --compilation-config '{"cudagraph_mode": "FULL_DECODE_ONLY"}' \
      --kv-transfer-config \
      '{"kv_connector": "MooncakeConnectorV1",
      "kv_role": "kv_consumer",
      "kv_port": "9000",
      "engine_id": "$MOONCAKE_ENGINE_ID",
      "kv_connector_module_path": "vllm_ascend.distributed.mooncake_connector",
      "kv_connector_extra_config": {
                "use_ascend_direct": true,
                "prefill": {
                        "dp_size": 2,
                        "tp_size": 8
                },
                "decode": {
                        "dp_size": 8,
                        "tp_size": 2
                }
          }
      }'