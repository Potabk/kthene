#!/bin/sh


nic_name="eth0"  # network card name
export POD_IP="172.17.0.7"
local_ip=$POD_IP
export VLLM_USE_MODELSCOPE=True
export HCCL_IF_IP=$local_ip
export GLOO_SOCKET_IFNAME=$nic_name
export TP_SOCKET_IFNAME=$nic_name
export HCCL_SOCKET_IFNAME=$nic_name
export OMP_PROC_BIND=false
export OMP_NUM_THREADS=10
export HCCL_BUFFSIZE=256
export TASK_QUEUE_ENABLE=1
export HCCL_OP_EXPANSION_MODE="AIV"
export MOONCAKE_ENGINE_ID="1"
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export VLLM_ENGINE_READY_TIMEOUT_S=1800
vllm serve vllm-ascend/DeepSeek-V3.2-W8A8 \
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
    --served-model-name ds-v32 \
    --max-model-len 40000 \
    --max-num-batched-tokens 16384 \
    --max-num-seqs 8 \
    --enforce-eager \
    --trust-remote-code \
    --gpu-memory-utilization 0.9  \
    --quantization ascend \
    --no-enable-prefix-caching \
    --tokenizer-mode deepseek_v32 \
    --tool-call-parser deepseek_v32 \
    --enable-auto-tool-choice \
    --reasoning-parser deepseek_v32 \
    --speculative-config '{"num_speculative_tokens": 1, "method":"deepseek_mtp"}' \
    --additional-config '{"recompute_scheduler_enable":true,"enable_shared_expert_dp": true}' \
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