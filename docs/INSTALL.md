# 鸿语 HarmonyOS 安装说明书

> 适用版本：鸿语 V1.0.0  
> 适用系统：HarmonyOS NEXT（HarmonyOS 5.0 及以上）  
> 更新日期：2026-11-23  
> 说明：本文是鸿语开发者编写的安装说明，不是华为官方文档。

## 1. 先看结论

HarmonyOS NEXT 与 Android 不同，**普通用户不能直接下载 HAP 后点击安装**。  
普通用户安装鸿语的正式方式是：

> **华为应用市场（AppGallery）搜索“鸿语” → 下载 → 安装**

截至本文更新时，鸿语仍在准备上架；应用市场链接要等审核通过后才生效。

| 用户类型 | 推荐安装方式 |
| --- | --- |
| 普通用户 | 华为应用市场 |
| 少量测试用户 | AGC 邀请测试 / 指定设备发布 |
| 开发者 | DevEco Studio 或 hdc 安装 debug HAP |
| 企业用户 | 企业 MDM / 内部应用分发 |

## 2. 安装前检查

- 设备为 HarmonyOS NEXT（HarmonyOS 5.0 及以上）
- 手机或平板已联网
- 设备有足够存储空间（建议至少 100 MB）
- 普通用户需要华为账号，用于应用市场下载
- 开发者需要电脑、数据线、DevEco Studio 或 hdc

查看系统版本：

> 设置 → 关于手机 → 软件版本

如果系统是 HarmonyOS 3.x/4.x，不属于本说明书的主要适用范围；鸿语按 HarmonyOS NEXT API 12 构建。

## 3. 方式一：华为应用市场安装（普通用户）

### 3.1 搜索安装

1. 打开 **华为应用市场**。
2. 搜索 **鸿语**。
3. 确认开发者为你的开发者主体，图标为蓝底白色对话气泡。
4. 点击 **安装**。
5. 安装完成后点击 **打开**。

### 3.2 通过分享链接安装

上架后，应用市场分享链接预计为：

```text
https://appgallery.huawei.com/app/detail?id=C6917622197744532417
```

华为设备也可以使用：

```text
store://appgallery.huawei.com/app/detail?id=C6917622197744532417
```

> 注意：应用未上架时，以上链接会提示“应用不存在”或无法打开。  
> 上架后请以 AGC 应用详情页复制的官方分享链接为准。

### 3.3 首次启动

1. 点击桌面“鸿语”图标。
2. 阅读隐私政策和用户协议，点击 **同意**。
3. 进入欢迎页。
4. 点击右上角设置，配置 DeepSeek API Key。
5. 返回首页开始对话。

## 4. 方式二：AGC 邀请测试 / 指定设备发布

适用于少量测试用户，不是普通用户的公开安装方式。

### 4.1 邀请测试

1. 开发者把测试版本上传到 AGC。
2. 在 AGC 创建邀请测试，添加测试用户华为账号。
3. 测试用户在应用市场“应用尝鲜”或邀请链接中安装。
4. 测试结束后，正式版本仍需走应用市场审核。

### 4.2 指定设备发布

1. 在 AGC 创建“指定设备发布”Profile。
2. 添加测试设备的 UDID。
3. 使用发布证书构建 `.app`。
4. 生成安装描述文件和 Deeplink。
5. 测试用户用华为浏览器打开 Deeplink 安装。

> 指定设备发布只对已登记 UDID 的设备有效，不能用于公开推广。

## 5. 方式三：开发者 hdc 安装（仅开发调试）

### 5.1 准备

- Windows 电脑
- DevEco Studio 或 HarmonyOS SDK 自带的 hdc
- 数据线
- 华为开发者账号
- 已签名的 **debug HAP**
- 目标设备 UDID 已加入调试 Profile

### 5.2 开启开发者模式

1. 设置 → 关于手机。
2. 连续点击 **版本号** 7 次。
3. 输入锁屏密码，开启开发者模式。
4. 设置 → 系统和更新 → 开发人员选项。
5. 打开 **USB 调试**。

### 5.3 连接设备

1. 用数据线连接电脑。
2. 手机弹窗选择 **传输文件**，允许 USB 调试。
3. 在电脑执行：

```bash
hdc list targets
```

能看到设备编号，说明连接成功。

### 5.4 安装 HAP

```bash
hdc install -r D:\path\to\HongYu-debug.hap
```

显示 `install bundle successfully` 即安装成功。

### 5.5 重要限制

- **release 签名的 HAP 不能直接本地安装。**
- **debug HAP 的 Profile 必须包含目标设备 UDID。**
- 不能把绑定自己设备的 debug HAP 发给别人安装。
- 不能把 AGC 上架用的 `.app` 当普通安装包分发。
- 修改签名、侧载、非官方渠道安装的风险由使用者承担。

## 6. 首次配置 DeepSeek API

1. 打开鸿语，点击右上角设置。
2. 进入 **模型服务**。
3. Base URL 保持：

```text
https://api.deepseek.com
```

4. 填入你的 DeepSeek API Key。
5. 模型选择 `deepseek-flash`（图片理解需要）。
6. 点击 **测试 DeepSeek API 连接**。
7. 显示成功后，点击 **保存设置**。
8. 返回首页发送“你好”测试。

API Key 只保存在本机，不写入安装包。费用由你的 DeepSeek 账号承担。

## 7. 升级与卸载

### 应用市场安装的版本

- 升级：应用市场 → 我的 → 更新，或应用详情页点击更新。
- 卸载：桌面长按鸿语图标 → 卸载；或设置 → 应用 → 鸿语 → 卸载。

### hdc 安装的调试版本

```bash
hdc uninstall com.hongyu.chat
```

卸载会删除应用沙箱内的对话、图片和 API Key。建议先导出需要保留的聊天记录。

## 8. 常见问题

### 应用市场搜不到鸿语

- 应用尚未上架或审核未通过。
- 当前账号所在地区不在发布范围。
- 设备类型不在支持范围（当前应用信息只勾选手机）。
- 应用市场缓存问题，下拉刷新或重启应用市场。

### 分享链接打不开

- 应用未上架时链接无效。
- 链接中的 App ID 需要 `C` 前缀。
- 请使用 AGC 应用详情页复制的官方分享链接。

### 下载 HAP 后无法安装

HarmonyOS NEXT 不支持普通用户直接点击 HAP 安装。  
请使用华为应用市场，或按第 5 节使用开发者方式安装。

### 安装报错 9568266 / INSTALL_FAILED_TEST_ONLY

通常是签名或 Profile 问题：

- debug Profile 未包含当前设备 UDID；
- 使用了 release 签名 HAP；
- 设备里已有同包名但签名不同的旧版本，先卸载再装；
- hdc/DevEco 版本与设备系统不匹配。

### 打开后没有回复

- 检查网络是否可访问 `api.deepseek.com`；
- 检查 API Key 是否正确、是否有余额；
- 在设置里点击“测试 DeepSeek API 连接”；
- 图片理解需要使用支持视觉的 `deepseek-flash`。

### 没有声音

- 检查系统媒体音量；
- 在线朗读需要网络和 API Key；
- 系统离线朗读依赖设备 Core Speech Kit，模拟器通常不可用。

## 9. 安全与免责声明

- 鸿语是第三方 DeepSeek API 客户端，不是 DeepSeek 官方应用。
- 本软件按 MIT License “AS IS” 提供，不附带任何担保。
- 下载、安装、使用本软件造成的设备、数据、账号、API 费用、AI 内容或法律风险，由使用者自行承担。
- 不要发送身份证号、银行卡号、密码等敏感个人信息。
- 不要从非官方渠道安装修改版、破解版或他人签名的包。

完整免责声明：

```text
https://github.com/allwell997/HongYu-HarmonyOS-AI/blob/main/DISCLAIMER.md
```

## 10. 获取帮助

- 项目主页：<https://github.com/allwell997/HongYu-HarmonyOS-AI>
- 问题反馈：GitHub Issues
- 源码下载：<https://github.com/allwell997/HongYu-HarmonyOS-AI/releases/latest>
- 客服邮箱：allwell997@163.com

> 反馈时请提供：设备型号、HarmonyOS 版本、鸿语版本、操作步骤、错误提示截图。不要发送 API Key。
