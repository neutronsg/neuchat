# WeChat Mini Program Integration

This integration supports WeChat Mini Program and Official Account customer service messages using the WeChat Customer Service API.

## API Documentation
- [WeChat Customer Service API](https://developers.weixin.qq.com/miniprogram/dev/OpenApiDoc/kf-mgnt/kf-message/sendCustomMessage.html)
- [WeChat Webhook Configuration](https://developers.weixin.qq.com/miniprogram/dev/framework/open-ability/customer-message/receive.html)

## Features Supported

### Incoming Message Types
- Text messages
- Image messages  
- Voice messages
- Video messages
- Location sharing
- Link sharing
- Mini Program cards

### Outgoing Message Types
- Text messages
- Image messages (via media upload)
- Voice messages (via media upload)
- Video messages (via media upload)
- Location information (as text)
- File attachments (as download links)

## Configuration

### 1. WeChat App Setup
1. Create a WeChat Mini Program or Official Account
2. Get your `app_id`, `app_secret`, and generate a `token`
3. Enable customer service functionality

### 2. Webhook Configuration
Configure the webhook URL in your WeChat backend:
```
URL: https://your-domain.com/webhooks/wechat/:token
Token: Your generated token (must match the token in channel configuration)
```

### 3. NeuChat Configuration
Create a WeChat channel in NeuChat with:
- **App ID**: Your WeChat app_id
- **App Secret**: Your WeChat app_secret  
- **Token**: Your webhook verification token
- **Encoding AES Key**: (Optional) For message encryption

## Message Flow

### Incoming Messages
1. User sends message via WeChat
2. WeChat sends webhook to `/webhooks/wechat/:token`
3. Webhook supports both JSON and XML formats
4. Message processed by `Wechat::IncomingMessageService`
5. Contact and conversation created/updated
6. Message appears in NeuChat inbox

### Outgoing Messages
1. Agent replies in NeuChat
2. Message sent via `Channel::Wechat#send_message_on_wechat`
3. Uses WeChat Customer Service API `/message/custom/send`
4. Supports text and media attachments

## Important Notes

- **Customer Service vs Official Account**: This integration is for customer service messages, not subscription management
- **OpenID**: User identification uses WeChat OpenID (automatically handled)
- **Media Files**: Images/videos uploaded to WeChat servers before sending
- **File Types**: Arbitrary files sent as download links (WeChat limitation)
- **Access Token**: Automatically managed with 2-hour expiry and refresh

## Supported Formats

The integration handles both:
- **JSON format** (newer WeChat API)
- **XML format** (legacy WeChat API)

Messages are processed consistently regardless of format.
