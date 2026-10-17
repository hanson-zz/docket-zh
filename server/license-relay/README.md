# 码头 Pro 授权中转（Cloudflare Worker）

码头 App 不能内置 Creem 的 API 密钥（代码是公开的），所以激活、校验、解绑都经这个小服务转发到 Creem。做法和兄弟应用拾掇的中转一样，区别是：

- Worker 名 `dockling-license`，健康检查返回 `{"ok":true,"service":"dockling-license"}`。
- 只认码头 Pro 的产品 `prod_XYf9P2X55fvYZQOLhs3Lr`。没设 `PRODUCT_ID` 变量时也用这个写死的 ID，不会放行别的产品；拾掇的许可证会被当作不存在，激活时占用的名额会立刻还回去。
- 赠送兑换码形如 `DKG-XXXX-XXXX-XXXX`（拾掇是 `SDG-`），记录里带 `product: "dockling"`。

App 里的地址集中在 `Sources/Core/ProLicense.swift` 的 `ProLicenseConfig.apiBase`，现在是：

```
https://dockling-license.tudou-123.workers.dev/v1/licenses/
```

部署后如果 Worker 地址不同（比如换了账号子域或绑了自己的域名），只改这一个常量。

## 接口

| 路径 | 方法 | 说明 |
| --- | --- | --- |
| `/` | GET | 健康检查 |
| `/v1/licenses/activate` | POST | `{ key, instance_name }` |
| `/v1/licenses/validate` | POST | `{ key, instance_id }` |
| `/v1/licenses/deactivate` | POST | `{ key, instance_id }` |
| `/admin` | GET | 兑换码管理页 |

返回格式：`{ activated|valid|deactivated: Bool, error?: String, instance: { id }, license_key: { status }, meta: { product_id } }`。

## 部署步骤（网页后台，不用装命令行）

1. **新建 Worker**：登录 Cloudflare ▸ Workers 和 Pages ▸ 创建 ▸ 创建 Worker，名字填 `dockling-license`，部署默认的 Hello World。然后点“编辑代码”，把本目录的 `worker.js` 整个粘进去，保存并部署。
2. **填 Creem API 密钥**：Worker ▸ 设置 ▸ 变量和机密 ▸ 添加，类型选“密钥”（Secret），名称 `CREEM_API_KEY`，值从 Creem 后台 ▸ Developers ▸ API Keys 复制（正式环境的密钥，不是测试的）。
3. **填产品 ID**：同一页添加一个普通变量（文本），名称 `PRODUCT_ID`，值 `prod_XYf9P2X55fvYZQOLhs3Lr`。（不填也只认这个 ID，填上更清楚。）测试时可再加 `CREEM_API = https://test-api.creem.io`，上线前删掉。
4. **兑换码 KV**：Cloudflare ▸ 存储和数据库 ▸ KV ▸ 创建命名空间，名字如 `dockling-gifts`（不要和拾掇的共用）。回到 Worker ▸ 设置 ▸ 绑定 ▸ 添加 ▸ KV 命名空间，变量名填 `GIFTS`，选刚建的命名空间。
5. **管理密码**：变量和机密里再加一个密钥 `ADMIN_TOKEN`，值自己定一个长一点的随机字符串（只有你知道）。
6. **验证**：浏览器打开 `https://dockling-license.<你的子域>.workers.dev/`，应看到 `{"ok":true,"service":"dockling-license"}`。地址如果不是 `tudou-123` 子域，改 App 里的 `ProLicenseConfig.apiBase`。
7. **生成兑换码**：打开 `<Worker 地址>/admin`，输入 `ADMIN_TOKEN`，填数量和备注，点“生成兑换码”。同一页可以“查看全部”（未使用 / 已激活 / 已作废）和作废某个码。每个码同一时间只能激活一台 Mac，在 App 的 设置 ▸ 码头 Pro 里“解绑本机”后可以换到另一台。

用命令行部署也可以：在本目录 `npx wrangler deploy`，再 `npx wrangler secret put CREEM_API_KEY`、`npx wrangler secret put ADMIN_TOKEN`，KV 的 ID 填进 `wrangler.toml` 的 `[[kv_namespaces]]`。

## Creem 后台

- 产品“码头 Pro”一次买断 $9.90，打开“许可证密钥”（License keys），激活上限建议 2 到 3 台。
- 早鸟价 $6.90：在 Creem 后台建一个优惠码（拾掇用的是 EARLYBIRD），或临时把价格改成 $6.90。App 里只显示价格，不内置优惠码。
- 购买链接：https://www.creem.io/payment/prod_XYf9P2X55fvYZQOLhs3Lr
