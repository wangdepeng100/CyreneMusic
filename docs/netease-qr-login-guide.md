# 网易云音乐扫码登录 API 逆向文档

本文档详细说明如何直接调用网易云音乐官方 API 实现扫码登录功能，适用于任何技术栈的项目集成。

---

## 概述

网易云音乐扫码登录流程分为三步：
1. **获取二维码 Key** - 从服务器获取唯一标识
2. **生成二维码** - 根据 Key 生成可扫描的二维码
3. **轮询检查状态** - 持续查询扫码状态直到成功或超时

---

## 公共请求头

所有请求都需要携带以下请求头：

```http
User-Agent: Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154
Referer: https://music.163.com/
Origin: https://music.163.com
Accept: application/json, text/plain, */*
Cookie: os=pc; appver=2.10.2.200154
```

> ⚠️ **重要**：`User-Agent` 必须模拟网易云桌面客户端，否则部分接口会返回错误。

---

## API 接口详解

### 1. 获取二维码 Key

**请求**
```http
GET https://music.163.com/api/login/qrcode/unikey?type=1&timestamp={timestamp}
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| type | number | 否 | 固定填 1 |
| timestamp | number | 是 | 当前时间戳（毫秒） |

**响应示例**
```json
{
  "code": 200,
  "unikey": "b5f9e8d7c6a5..."
}
```

**响应字段**
| 字段 | 说明 |
|------|------|
| code | 200 表示成功 |
| unikey | 二维码唯一标识，后续接口都需要此值 |

---

### 2. 生成二维码图片

**请求**
```http
GET https://music.163.com/api/login/qrcode/create?key={unikey}&qrimg=true&timestamp={timestamp}
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| key | string | 是 | 上一步获取的 unikey |
| qrimg | boolean | 否 | 设为 true 时返回 Base64 图片 |
| timestamp | number | 是 | 当前时间戳 |

**响应示例**
```json
{
  "code": 200,
  "data": {
    "qrimg": "data:image/png;base64,iVBORw0KGgo..."
  }
}
```

**手动生成二维码**

如果不使用 `qrimg=true`，可以自行生成二维码，内容为：
```
https://music.163.com/login?codekey={unikey}
```

---

### 3. 检查扫码状态

**请求**
```http
GET https://music.163.com/api/login/qrcode/client/login?key={unikey}&type=1&timestamp={timestamp}
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| key | string | 是 | unikey |
| type | number | 否 | 固定填 1 |
| timestamp | number | 是 | 当前时间戳 |

**备用接口**（如果上述接口失败）：
```http
GET https://music.163.com/api/login/qrcode/client/check?key={unikey}&timestamp={timestamp}
```

**状态码说明**
| code | 说明 |
|------|------|
| 800 | 二维码已过期，需重新获取 |
| 801 | 等待扫码 |
| 802 | 已扫码，等待用户在手机上确认 |
| 803 | 授权登录成功 |

**成功响应示例（code=803）**
```json
{
  "code": 803,
  "message": "授权登录成功",
  "cookie": "MUSIC_U=abc123...; __csrf=xyz789...",
  "profile": {
    "userId": 123456789,
    "nickname": "用户昵称",
    "avatarUrl": "https://p1.music.126.net/..."
  }
}
```

> 💡 **提示**：成功时的 `cookie` 字段包含登录凭证，需妥善保存用于后续 API 调用。

---

### 4. 获取用户信息（可选）

登录成功后，可使用 Cookie 获取更详细的用户信息：

**请求**
```http
GET https://music.163.com/api/nuser/account/get
Cookie: {登录成功返回的cookie}
```

**响应示例**
```json
{
  "code": 200,
  "profile": {
    "userId": 123456789,
    "nickname": "用户昵称",
    "avatarUrl": "https://p1.music.126.net/...",
    "vipType": 11
  }
}
```

---

## 完整代码示例

### Node.js / TypeScript

```typescript
import axios from 'axios';

const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154',
  'Referer': 'https://music.163.com/',
  'Origin': 'https://music.163.com',
  'Cookie': 'os=pc; appver=2.10.2.200154',
};

// 1. 获取二维码 Key
async function getQrKey(): Promise<string> {
  const url = `https://music.163.com/api/login/qrcode/unikey?type=1&timestamp=${Date.now()}`;
  const resp = await axios.get(url, { headers: HEADERS });
  
  if (resp.data.code !== 200) {
    throw new Error('获取二维码Key失败');
  }
  return resp.data.unikey;
}

// 2. 生成二维码图片
async function createQrImage(key: string): Promise<string> {
  const url = `https://music.163.com/api/login/qrcode/create?key=${key}&qrimg=true&timestamp=${Date.now()}`;
  const resp = await axios.get(url, { headers: HEADERS });
  
  // 返回 Base64 图片或自行生成
  return resp.data?.data?.qrimg || `https://music.163.com/login?codekey=${key}`;
}

// 3. 检查扫码状态
async function checkQrStatus(key: string): Promise<{
  code: number;
  message?: string;
  cookie?: string;
  profile?: { userId: string; nickname: string; avatarUrl: string };
}> {
  const url = `https://music.163.com/api/login/qrcode/client/login?key=${key}&type=1&timestamp=${Date.now()}`;
  const resp = await axios.get(url, { headers: HEADERS });
  
  const data = resp.data;
  return {
    code: data.code,
    message: data.message,
    cookie: data.cookie,
    profile: data.profile,
  };
}

// 主流程
async function qrLogin() {
  // 获取 Key
  const key = await getQrKey();
  console.log('获取到 Key:', key);

  // 生成二维码
  const qrImage = await createQrImage(key);
  console.log('二维码生成成功，请用网易云音乐 APP 扫码');
  console.log('二维码内容:', `https://music.163.com/login?codekey=${key}`);

  // 轮询检查状态
  const poll = setInterval(async () => {
    const status = await checkQrStatus(key);
    console.log('状态:', status.code, status.message);

    switch (status.code) {
      case 800:
        console.log('二维码已过期，请重新获取');
        clearInterval(poll);
        break;
      case 801:
        console.log('等待扫码...');
        break;
      case 802:
        console.log('已扫码，请在手机上确认登录');
        break;
      case 803:
        console.log('登录成功！');
        console.log('Cookie:', status.cookie);
        console.log('用户信息:', status.profile);
        clearInterval(poll);
        break;
    }
  }, 2000);
}

qrLogin();
```

### Python

```python
import requests
import time

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154',
    'Referer': 'https://music.163.com/',
    'Origin': 'https://music.163.com',
    'Cookie': 'os=pc; appver=2.10.2.200154',
}

def get_qr_key():
    """获取二维码 Key"""
    url = f'https://music.163.com/api/login/qrcode/unikey?type=1&timestamp={int(time.time() * 1000)}'
    resp = requests.get(url, headers=HEADERS)
    data = resp.json()
    if data['code'] != 200:
        raise Exception('获取二维码Key失败')
    return data['unikey']

def create_qr_image(key):
    """生成二维码图片"""
    url = f'https://music.163.com/api/login/qrcode/create?key={key}&qrimg=true&timestamp={int(time.time() * 1000)}'
    resp = requests.get(url, headers=HEADERS)
    data = resp.json()
    return data.get('data', {}).get('qrimg') or f'https://music.163.com/login?codekey={key}'

def check_qr_status(key):
    """检查扫码状态"""
    url = f'https://music.163.com/api/login/qrcode/client/login?key={key}&type=1&timestamp={int(time.time() * 1000)}'
    resp = requests.get(url, headers=HEADERS)
    return resp.json()

def qr_login():
    # 1. 获取 Key
    key = get_qr_key()
    print(f'获取到 Key: {key}')

    # 2. 生成二维码
    qr_url = f'https://music.163.com/login?codekey={key}'
    print(f'请用网易云音乐 APP 扫描此链接生成的二维码: {qr_url}')

    # 3. 轮询检查状态
    while True:
        status = check_qr_status(key)
        code = status['code']
        
        if code == 800:
            print('二维码已过期')
            break
        elif code == 801:
            print('等待扫码...')
        elif code == 802:
            print('已扫码，等待确认...')
        elif code == 803:
            print('登录成功！')
            print(f"Cookie: {status.get('cookie')}")
            print(f"用户信息: {status.get('profile')}")
            break
        
        time.sleep(2)

if __name__ == '__main__':
    qr_login()
```

---

## 流程时序图

```
┌──────────┐          ┌──────────────────────┐          ┌──────────────┐
│  客户端  │          │ music.163.com API    │          │  网易云APP   │
└────┬─────┘          └──────────┬───────────┘          └──────┬───────┘
     │                           │                              │
     │  GET /api/login/qrcode/unikey                            │
     │─────────────────────────>│                              │
     │                           │                              │
     │  { code:200, unikey:"xxx" }                             │
     │<─────────────────────────│                              │
     │                           │                              │
     │  GET /api/login/qrcode/create?key=xxx&qrimg=true        │
     │─────────────────────────>│                              │
     │                           │                              │
     │  { code:200, data:{qrimg:"..."} }                       │
     │<─────────────────────────│                              │
     │                           │                              │
     │  [显示二维码]              │                              │
     │                           │                              │
     │                           │         用户扫码             │
     │                           │<────────────────────────────│
     │                           │                              │
     ├───────── 轮询 ────────────┤                              │
     │                           │                              │
     │  GET /api/login/qrcode/client/login?key=xxx             │
     │─────────────────────────>│                              │
     │                           │                              │
     │  { code:801 } 等待扫码    │                              │
     │<─────────────────────────│                              │
     │                           │                              │
     │  GET /api/login/qrcode/client/login?key=xxx             │
     │─────────────────────────>│                              │
     │                           │                              │
     │  { code:802 } 等待确认    │        用户点击确认          │
     │<─────────────────────────│<────────────────────────────│
     │                           │                              │
     │  GET /api/login/qrcode/client/login?key=xxx             │
     │─────────────────────────>│                              │
     │                           │                              │
     │  { code:803, cookie:"...", profile:{...} }              │
     │<─────────────────────────│                              │
     │                           │                              │
     │  [保存Cookie，登录完成]    │                              │
     └───────────────────────────┴──────────────────────────────┘
```

---

## 注意事项

1. **请求频率**：轮询间隔建议 1.5-2 秒，过快可能被限流
2. **二维码有效期**：约 3 分钟，过期需重新获取
3. **Cookie 有效期**：通常较长（数月），但可能因安全策略失效
4. **User-Agent**：必须模拟网易云桌面客户端，否则返回错误
5. **X-Real-IP**：部分场景下添加中国大陆 IP 头可提升成功率

---

## 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| code: 8821 | 接口版本过旧 | 尝试备用接口 `/client/check` |
| code: 404 | 接口不存在 | 检查 URL 拼写 |
| code: 500 | 服务器错误 | 稍后重试 |
| "升级新版本" | UA 不符合要求 | 使用正确的桌面客户端 UA |

---