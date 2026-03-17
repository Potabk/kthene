# Qwen3-235B多节点

## 1. 服务拉起

双机16卡pd分离, 参数参考[config_map](./config.yaml)

## 基础功能验证

```shell
curl http://kthena-router/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "你好，帮我分析下下列代码的功能：\n```\nimport torch\n\nx = torch.tensor([1.0, 2.0, 3.0])\ny = torch.tensor([4.0, 5.0, 6.0])\n\nresult = x + y\nprint(result)\n```"}],
    "max_completion_tokens": 512,
    "stream": true
  }'
```


## using router:

```shell
vllm bench serve \
  --base-url http://kthena-router \
  --model Qwen/Qwen3-235B-A22B \
  --served-model-name qwen3 \
  --endpoint /v1/completions \
  --dataset-name random \
  --random-input 2048 \
  --random-output 1024 \
  --request-rate 10 \
  --num-prompt 100

============ Serving Benchmark Result ============
Successful requests:                     57        
Failed requests:                         43        
Request rate configured (RPS):           10.00     
Benchmark duration (s):                  75.53     
Total input tokens:                      116736    
Total generated tokens:                  58368     
Request throughput (req/s):              0.75      
Output token throughput (tok/s):         772.74    
Peak output token throughput (tok/s):    1095.00   
Peak concurrent requests:                57.00     
Total token throughput (tok/s):          2318.21   
---------------Time to First Token----------------
Mean TTFT (ms):                          4045.37   
Median TTFT (ms):                        4192.43   
P99 TTFT (ms):                           5561.79   
-----Time per Output Token (excl. 1st token)------
Mean TPOT (ms):                          59.23     
Median TPOT (ms):                        59.31     
P99 TPOT (ms):                           59.52     
---------------Inter-token Latency----------------
Mean ITL (ms):                           59.23     
Median ITL (ms):                         0.00      
P99 ITL (ms):                            1038.71   
==================================================
```


## using proxy

```shell
python load_balance_proxy_server_example.py --host localhost --prefiller-hosts 172.22.5.112 --prefiller-ports 7100 --decoder-hosts 172.22.5.206 --decoder-ports 7100

vllm bench serve \
  --base-url http://localhost:8000 \
  --model Qwen/Qwen3-235B-A22B \
  --served-model-name qwen3 \
  --endpoint /v1/completions \
  --dataset-name random \
  --random-input 2048 \
  --random-output 1024 \
  --request-rate 10 \
  --num-prompt 100

============ Serving Benchmark Result ============
Successful requests:                     100       
Failed requests:                         0         
Request rate configured (RPS):           10.00     
Benchmark duration (s):                  79.63     
Total input tokens:                      204800    
Total generated tokens:                  102400    
Request throughput (req/s):              1.26      
Output token throughput (tok/s):         1285.89   
Peak output token throughput (tok/s):    1600.00   
Peak concurrent requests:                100.00    
Total token throughput (tok/s):          3857.66   
---------------Time to First Token----------------
Mean TTFT (ms):                          3426.51   
Median TTFT (ms):                        3591.30   
P99 TTFT (ms):                           5018.22   
-----Time per Output Token (excl. 1st token)------
Mean TPOT (ms):                          63.73     
Median TPOT (ms):                        63.87     
P99 TPOT (ms):                           64.08     
---------------Inter-token Latency----------------
Mean ITL (ms):                           63.73     
Median ITL (ms):                         64.33     
P99 ITL (ms):                            70.88     
==================================================
```
