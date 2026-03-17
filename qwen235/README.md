# Qwen235B动态扩缩容

vllm bench serve \
  --base-url http://kthena-router \
  --model Qwen/Qwen3-235B-A22B  \
  --served-model-name qwen235 \
  --endpoint /v1/completions \
  --dataset-name random \
  --random-input 2048 \
  --random-output 1024 \
  --request-rate 10 \
  --num-prompt 100

curl http://kthena-router/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen235",
    "messages": [{"role": "user", "content": "你好，帮我分析下下列代码的功能：\n```\nimport torch\n\nx = torch.tensor([1.0, 2.0, 3.0])\ny = torch.tensor([4.0, 5.0, 6.0])\n\nresult = x + y\nprint(result)\n```"}],
    "max_completion_tokens": 512
  }'