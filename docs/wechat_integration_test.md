# WeChat Mini Program Integration Test Flow

## Test Incoming Message Flow

### 1. Simulate WeChat Webhook (JSON format)
```bash
curl -X POST http://localhost:3000/webhooks/wechat/your_token \
  -H "Content-Type: application/json" \
  -d '{
    "ToUser": "your_app_id",
    "FromUser": "test_openid_12345", 
    "CreateTime": 1640995200,
    "MsgType": "text",
    "Content": "Hello from WeChat customer!",
    "MsgId": 1234567890
  }'
```

### 2. Expected Result
- ✅ Contact created with `source_id: "test_openid_12345"`
- ✅ Conversation created with `wechat_openid: "test_openid_12345"`
- ✅ Message created with content: "Hello from WeChat customer!"
- ✅ Message appears in NeuChat inbox

## Test Outgoing Message Flow

### 1. Agent Replies in NeuChat
- Agent types reply: "Thank you for your message!"
- Agent sends the message

### 2. Expected Flow
- ✅ Message created with `message_type: :outgoing`
- ✅ `after_create_commit` callback triggered
- ✅ `SendReplyJob` queued
- ✅ `Wechat::SendOnWechatService` called
- ✅ WeChat Customer Service API called:

```json
POST https://api.weixin.qq.com/cgi-bin/message/custom/send?access_token=ACCESS_TOKEN
{
  "touser": "test_openid_12345",
  "msgtype": "text",
  "text": {
    "content": "Thank you for your message!"
  }
}
```

### 3. Expected Result
- ✅ Message sent to WeChat user
- ✅ Message `source_id` updated with WeChat `msgid`
- ✅ Message status remains `sent` (or `failed` if error)

## Test Attachment Flow

### 1. Agent Sends Image in NeuChat
- Agent uploads and sends image

### 2. Expected Flow
- ✅ Image uploaded to WeChat servers via `/media/upload`
- ✅ Customer Service API called with `media_id`
- ✅ Image delivered to WeChat user

## Error Handling

### Test Invalid Token
```bash
curl -X POST http://localhost:3000/webhooks/wechat/invalid_token \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

Expected: HTTP 404 "Channel not found"

### Test Invalid JSON
```bash
curl -X POST http://localhost:3000/webhooks/wechat/your_token \
  -H "Content-Type: application/json" \
  -d 'invalid json'
```

Expected: Logged error, webhook ignored

## Verification Points

1. **SendReplyJob Integration**: ✅ Added `Channel::Wechat` to services list
2. **Service Creation**: ✅ Created `Wechat::SendOnWechatService`
3. **Channel Name**: ✅ Updated to "WeChat Mini Program"
4. **Message Flow**: ✅ Incoming creates contact/conversation, outgoing triggers API call
5. **OpenID Handling**: ✅ Stored in contact `source_id`, used for outgoing messages
