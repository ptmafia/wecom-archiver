# wecom-reader

在后台把企业微信（WeCom）Mac 版的聊天记录读下来，原文存在自己电脑上，方便搜索，或交给 AI 助手整理。

- **不用官方接口。** 通过 macOS 的辅助功能读界面上的文字，海外企业、没有管理员权限也能用。
- **不打扰你。** 企微在最前面时不动；离开企微满 1 分钟才开始读；切回企微，1 秒内停手，并把会话列表放回最上面。
- **不替你「已读」。** 有未读的单聊、@ 了你的群一律不打开，等你自己看过再读。没 @ 你的群照常读。
- **只增不减。** 新读到的内容和已有存档对齐后合并，对不上的留空位、以后补齐，不覆盖旧记录；每天备份，留 7 天。
- **只在本机。** 不联网、不上传，也不会发消息。

第一次会先把每个会话最近的几屏读一遍，然后在你不用企微时慢慢往前补历史；全部读完后，每天只读有新消息的会话。

## 安装

需要 macOS 14 以上。

1. 从 [Releases](../../releases) 下载 zip 并解压，或者自己编译（见下）。
2. 双击 `安装.command`。提示「无法验证开发者」时：系统设置 → 隐私与安全性 → 「仍要打开」。
3. 按提示填你在企微里显示的名字（用来认出 @ 你的消息和你自己发的消息，可以跳过）。
4. 在自动打开的「辅助功能」里打开 `wecom-reader-launcher`。

之后不用管它。卸载：双击 `卸载.command`。聊天记录会留着，要删就删 `~/Library/Application Support/wecom-reader/`。

## 自己编译

```bash
swift test
./deploy/package.sh ~/Desktop/wecom-reader
```

生成的文件夹里就是安装包（arm64 + x86_64）。

## 用法

```bash
WR="$HOME/Library/Application Support/wecom-reader/bin/wecom-reader"
"$WR" status              # 读了多少
"$WR" unread              # 哪些会话留着等你先读
"$WR" search 关键词 [--conv 会话名] [--limit N]
```

## 数据

都在 `~/Library/Application Support/wecom-reader/`（权限 700）：

| 文件 | 内容 |
|---|---|
| `archive/<会话名>.jsonl` | 一行一条消息：`at` `sender` `kind` `text` `quote` `files` `links`；`kind=gap` 表示这里还缺一段 |
| `state.json` | 每个会话读到哪 |
| `backup/` | 每天一份备份，留 7 天 |
| `logs/reader.log` | 只记会话名和条数，不记内容 |

## 已知限制

- 锁屏时 macOS 会清空窗口内容，读不了。要整夜读，请关掉自动锁屏和屏保。
- 企微主窗口要开着（被别的窗口盖住没关系），并停在「消息」页。
- 正在读某个会话的那几秒里，对方刚好发来的新消息会被企微标成已读。
- 同名的两个会话暂时都不读。
- 界面只测过日文版企微，简体中文、繁体中文、英文按企微自带的文字表写了规则，但没在真机上跑过。
- 图片里的文字默认不读。

## 说明

本项目与腾讯无关，不是企业微信官方产品。聊天记录涉及他人，使用前请确认所在公司的信息安全规定。

---

## English

wecom-reader quietly archives your WeCom (WeChat Work) chats on macOS, through the Accessibility API, while you are not using WeCom. It never opens unread private chats or groups that mention you, never overwrites what it has already saved, and keeps everything on your Mac. Build with `swift test && ./deploy/package.sh <folder>`, then run `安装.command` (install) in that folder and allow `wecom-reader-launcher` under Accessibility.

## License

MIT
