# Test examples for WeChat Customer Service integration

## JSON Format (New API)
```json
{
  "ToUser": "your_app_id",
  "FromUser": "user_openid", 
  "CreateTime": 1640995200,
  "MsgType": "text",
  "Content": "Hello from customer service",
  "MsgId": 1234567890
}
```

## XML Format (Legacy API)
```xml
<xml>
  <ToUserName><![CDATA[your_app_id]]></ToUserName>
  <FromUserName><![CDATA[user_openid]]></FromUserName>
  <CreateTime>1640995200</CreateTime>
  <MsgType><![CDATA[text]]></MsgType>
  <Content><![CDATA[Hello from customer service]]></Content>
  <MsgId>1234567890</MsgId>
</xml>
```

## Image Message (JSON)
```json
{
  "ToUser": "your_app_id",
  "FromUser": "user_openid",
  "CreateTime": 1640995200,
  "MsgType": "image",
  "PicUrl": "https://example.com/image.jpg",
  "MediaId": "media_id_123",
  "MsgId": 1234567891
}
```

## Mini Program Card (JSON)
```json
{
  "ToUser": "your_app_id", 
  "FromUser": "user_openid",
  "CreateTime": 1640995200,
  "MsgType": "miniprogrampage",
  "Title": "Mini Program Title",
  "AppId": "miniprogram_app_id",
  "PagePath": "pages/index/index",
  "ThumbMediaId": "thumb_media_id",
  "MsgId": 1234567892
}
```

## Customer Service Reply (JSON)
```json
{
  "touser": "user_openid",
  "msgtype": "text", 
  "text": {
    "content": "Thank you for your message!"
  }
}
```

## Customer Service Image Reply (JSON)
```json
{
  "touser": "user_openid",
  "msgtype": "image",
  "image": {
    "media_id": "uploaded_media_id"
  }
}
```
