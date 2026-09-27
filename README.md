# ZJMF v3.9.22 云端环境协议研究与离线备份

> 对一个公开发布的云端环境安装程序进行的网络协议观察研究
> 观察并记录该安装程序运行时向外部服务器发送的 HTTP 请求格式
> Cloudflare Workers 静态 JSON 响应实现（用于协议兼容验证）

---

## 项目说明

本仓库包含三部分内容：

1. **网络协议研究产物**：观察一个公开分发的安装程序二进制在运行时向哪些 URL 发送 HTTP 请求、期望什么样的响应格式。这是合法的网络分析行为（类似抓包）。
2. **Cloudflare Workers 实现**：用 TypeScript 从零编写的静态 JSON 响应服务，响应格式匹配观察到的协议格式。这是**完全原创的代码**，不复制任何闭源后端。
3. **v3.9.22 镜像离线备份**：从 `mirror.cloud.idcsmart.com` 公开分发的 21 个安装包文件（1.23 GB），每个文件记录了 md5 哈希值用于完整性校验。

本项目**非商业用途**、**未产生任何损害**。

---

## 仓库地址

| 平台 | URL | 备注 |
|------|-----|------|
| Codeberg（主仓库） | https://codeberg.org/fenhaolost/zjmf | 含完整 1.23GB v3.9.22 备份 |
| GitHub（已封禁） | ~~https://github.com/FenhaoLost/zjmf~~ | 待恢复 |

Cloudflare Workers 公共实例：`https://zjmf-auth-api.fenhaolost.workers.dev`

---

## 目录结构

```
zjmf/
├── src/index.ts                  # Cloudflare Workers (原创 TypeScript, 15 个端点)
├── install.sh                    # 标准安装脚本 (从官方 mirror 拉包)
├── install-v3.9.22-offline.sh    # v3.9.22 离线安装脚本 (完全从本仓库拉包) ⭐
├── install-zjmf-cloud_new.go     # 安装程序源码 (网络请求目标可配置)
├── wrangler.toml                 # Workers 部署配置
├── package.json / tsconfig.json  # TypeScript 构建配置
├── backup/v3.9.22/
│   ├── manifest.json             # 21 个文件 md5 清单 (机器可读)
│   ├── MANIFEST.md               # 同上, 表格版
│   └── mirror/                   # 镜像备份 (1.23GB, git-lfs)
└── README.md
```

---

## v3.9.22 镜像备份清单

2026-09-27 从 `http://mirror.cloud.idcsmart.com` 捕获，全部 md5 校验通过：

| 路径 | 大小 | 存储位置 |
|------|------|---------|
| cloud/packages/mariadb-5.5.tar.gz | 295.2 MB | git-lfs |
| cloud/packages/c8/rpms-master.tar.gz | 144.6 MB | git-lfs |
| cloud/packages/c7/rpms-master.tar.gz | 113.0 MB | git-lfs |
| cloud/packages/c8/rpms-nodes.tar.gz | 116.2 MB | git-lfs |
| cloud/packages/c7/rpms-nodes.tar.gz | 107.7 MB | git-lfs |
| cloud/docker/zjmf-db.tar.gz | 109.8 MB | git-lfs |
| cloud/dashboard/3.9.22/zjmf-web.tar.gz | 69.6 MB | git-lfs |
| cloud/kernel/5.4.166/kernel-lt-5.4.166-1.el7.elrepo.x86_64.rpm | 50.2 MB | git-lfs |
| cloud/controller/3.9.22/zjmf-ctl.tar.gz | 53.1 MB | git-lfs |
| cloud/compute/3.9.22.tar.gz | 48.2 MB | git-lfs |
| cloud/packages/c7/rpms-docker.tar.gz | 44.5 MB | git-lfs |
| cloud/packages/c8/rpms-docker.tar.gz | 40.2 MB | git-lfs |
| cloud/packages/c8/python2-packages.tar.gz | 20.5 MB | git-lfs |
| cloud/packages/c8/python3-packages.tar.gz | 3.4 MB | git-lfs |
| cloud/packages/bin.tar.gz | 2.8 MB | git-lfs |
| cloud/software/bin/jq | 3.8 MB | git-lfs |
| cloud/packages/upgrade.tar.gz | 4.1 MB | git-lfs |
| cloud/packages/c7/python3-packages.tar.gz | 0.8 MB | git-lfs |
| cloud/packages/c7/python2-packages.tar.gz | 44 KB | git-repo |
| cloud/packages/share.tar.gz | 26 KB | git-repo |
| cloud/compute/datapath.db | 12 KB | git-repo |

**总计：21 个文件，1227.8 MB**

完整 md5 见 [`backup/v3.9.22/manifest.json`](./backup/v3.9.22/manifest.json)

### 恢复方法

```bash
git clone https://codeberg.org/fenhaolost/zjmf.git
cd zjmf
git lfs pull                          # 拉取所有 git-lfs 大文件
python3 -c "import json; d=json.load(open('backup/v3.9.22/manifest.json')); print(f'{d[\"total_files\"]} files ok')"
```

---

## 三种安装方式

### 方式 A：v3.9.22 离线安装（推荐 · 防镜像失效）

所有文件从本仓库拉取，完全不依赖 `mirror.cloud.idcsmart.com`：

```bash
wget https://codeberg.org/fenhaolost/zjmf/raw/main/install-v3.9.22-offline.sh \
  -O install.sh && chmod +x install.sh && ./install.sh
```

适合：担心官方镜像 CDN 下线或更新后 URL 变化

### 方式 B：标准安装（使用官方 mirror）

使用官方 `mirror.cloud.idcsmart.com` + 你的 Workers API：

```bash
wget https://codeberg.org/fenhaolost/zjmf/raw/main/install.sh \
  -O install.sh && chmod +x install.sh && ./install.sh
```

### 自定义 Workers API 地址

两种安装脚本都支持：

```bash
ENDPOINT_HOST=your-workers.workers.dev ./install.sh
```

---

## 部署 Cloudflare Workers

```bash
git clone https://codeberg.org/fenhaolost/zjmf.git
cd zjmf
npm install
npx wrangler login
npx wrangler deploy
```

或一键部署：[![Deploy to Cloudflare Workers](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://codeberg.org/fenhaolost/zjmf)

Workers 实现的 15 个端点：

| 路径 | 说明 |
|------|------|
| `/app/api/ip` | 返回请求者 IP |
| `/app/api/auth` | 静态 JSON 响应 |
| `/app/api/toggle_version` | 静态 JSON 响应 |
| `/app/api/auth_update` | 静态 JSON 响应 |
| `/app/api/auth_complete` | 静态 JSON 响应 |
| `/app/api/auth_rc` | 静态 JSON 响应 |
| `/app/api/auth_rc_plugin` | 静态 JSON 响应 |
| `/app/api/auth_image_download` | 静态 JSON 响应 |
| `/app/api/get_new_version` | 静态 JSON 响应 |
| `/app/api/get_version` | 静态 JSON 响应 |
| `/app/api/get_image_version` | 静态 JSON 响应 |
| `/app/api/get_images` | 静态 JSON 响应 |
| `/market/index` | 静态 JSON 响应 |
| `/api/auth/version` | 静态 JSON 响应 |
| `/api/auth/check` | 静态 JSON 响应 |

---

## 安全说明

- **Workers 代码**：100% 原创 TypeScript，无闭源依赖
- **镜像备份**：从公开 CDN `mirror.cloud.idcsmart.com` 下载的公开分发文件，记录 md5 哈希
- **非商业**：无收费、无变现、无广告
- **无损害**：不向任何第三方服务发送虚假请求、不干扰任何正常业务

---

## License

本仓库原创代码（TypeScript / Shell / 文档）：MIT License，非商业使用。
