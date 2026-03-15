#!bin/sh

curl http://<SERVICE_IP>:7100/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ds_r1",
    "messages": [{"role": "user", "content": "你好"}],
    "max_tokens": 512
  }'



curl http://10.247.148.69/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ds_r1",
    "messages": [{"role": "user", "content": "你好"}],
    "max_tokens": 512
  }'
