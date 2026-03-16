#!bin/sh

curl http://<SERVICE_IP>:7100/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ds_r1",
    "messages": [{"role": "user", "content": "你好"}],
    "max_completion_tokens": 512
  }'



curl http://kthena-router/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-5",
    "messages": [{"role": "user", "content": "你好，帮我分析下下列代码的功能：\n```\nimport torch\n\nx = torch.tensor([1.0, 2.0, 3.0])\ny = torch.tensor([4.0, 5.0, 6.0])\n\nresult = x + y\nprint(result)\n```"}],
    "max_completion_tokens": 512
  }'


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
