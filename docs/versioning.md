# Version And Build Rules / 版本与构建号规则

Effective from V2.10.2, released on 2026-10-17.

自 2026-10-17 发布的 V2.10.2 起采用以下规则。

## 中文

### 版本号与构建号

- `MARKETING_VERSION` / `CFBundleShortVersionString` 存放完整版本，例如 `2.10.1`、`2.11.0`，公开标签仍为 `vX.Y.Z`。
- `CURRENT_PROJECT_VERSION` / `CFBundleVersion` 存放独立、全局递增的发布构建序号，使用四位十进制字符串，例如 `0030` 后为 `0031`。前导零只影响显示；比较时按数值处理。
- 构建号不再作为公开版本的第三段，也不随主版本或次版本归零。App、更新清单中的 `sparkle:version` 和发布说明必须使用一致的四位字符串。
- 设置默认隐藏构建号；开启“开发者选项 → 显示构建号”后，在当前版本下方显示。
- 这里的计数单位是准备对外分发的发布构建。普通 Debug 编译、单元测试和同一候选构建的重复验证不自动消耗编号；它不是所有 Xcode 编译操作的次数。

### 历史核对与迁移

2026-10-17 通过 GitHub Releases API 的完整分页列表核对，共有 **41 次已发布正式 Release**，没有草稿或预发布版本。最早为 `v1.0.2`，最新为 `v2.10.1`；`CHANGELOG.md` 的 41 条版本记录和 `docs/releases/` 的 41 份完整发布说明与该列表一致。明细保存在 [ReleaseBuilds.json](../Configuration/ReleaseBuilds.json) 的历史基线中。

历史上没有记录全部本地编译次数，因此采用这 41 次可验证的发布构建作为一次性的迁移基线，下一发布构建预留为 **`0042`**。基线序号 `0041` 不代表历史 `v2.10.1` 当时写入了这个值：它实际使用 Version `2.10`、Build `1`。已发布的安装包、标签和历史发布说明保持原样。

已发布的 V2.10.2 使用完整版本 `2.10.2`、Build `0042`，复用迁移时预留的编号。V2.10.3 使用 Build `0043`，V2.10.4 使用 `0044`；V2.10.5 分配 Build `0045`，实际发布状态见构建号分配记录；下一次新的发布构建为 `0046`。

原开发编号 `1000` 没有公开发布，不作为累计次数或后续编号的基线。若本地装有该开发构建，应手动替换为新构建，不能期待 Sparkle 将 `0042` 判定为比 `1000` 更新。

### 后续发布

1. 核对最新 GitHub Release、构建号分配记录和实际分发 App 的元数据，不根据补丁号或本地标签数量推算次数。
2. 同一次未完成的发布准备复用已预留编号；`0042` 已绑定 V2.10.2，不因首次确定版本号而再加一。新的分发构建取已分配最大序号加一，按十进制计算后格式化为四位。已经对外分发或放弃的编号保留记录，不因删除 Release 或修改营销版本而复用。
3. 在 [ReleaseBuilds.json](../Configuration/ReleaseBuilds.json) 中记录编号及状态；预留时不虚构版本或标签，发布后补齐实际版本、标签，并将状态改为 `published`。历史基线只记录本次迁移，不在每次发布后重新编号。
4. 同步 App target 的 Debug/Release 配置；测试 target 的独立版本配置不计入发布构建。
5. 验证生成的 `Info.plist` 和签名 appcast 保留前导零，且构建号数值严格递增。迁移后的首个更新包准备使用 `--previous-build 0041`；以后按实际上一分发构建传值。
6. 每次发布的中英文 Markdown 都写明完整版本和四位 Build，并解释 Build 为独立递增的发布构建序号，不再拼入版本号。README 链接本规则，累计日志不把未发布构建写成已发布版本。

编号达到 `9999` 后需先制定新规则，不能截断或回绕到 `0000`。

核对命令：

```sh
gh api --paginate --slurp repos/LexTheAries2209/Capricorn/releases \
  --jq '[.[][] | select(.draft == false and .prerelease == false)] | length'
```

## English

`MARKETING_VERSION` / `CFBundleShortVersionString` contains the complete public version, such as `2.11.0`. `CURRENT_PROJECT_VERSION` / `CFBundleVersion` is an independent, globally increasing release-build sequence formatted as four decimal digits: `0030` is followed by `0031`. Build numbers are compared numerically and are never appended to the public version or reset for a new marketing version. The App, appcast `sparkle:version`, and release notes must agree, including leading zeros.

The October 17, 2026 audit found **41 published stable GitHub Releases**, from `v1.0.2` through `v2.10.1`, matching 41 changelog entries and 41 combined release-note files at that time. This verified release history provides the migration baseline; the complete count of past local compilations is unavailable. **V2.10.2 uses Build `0042`, V2.10.3 uses `0043`, V2.10.4 uses `0044`, V2.10.5 is allocated `0045`, and the next new release build is `0046`.** The ledger records publication status. Debug builds, tests, and repeated validation of the same candidate do not automatically allocate another number.

Historical ordinal 41 is not a claim that `v2.10.1` shipped with Build `0041`; its actual metadata was Version `2.10`, Build `1`. Existing releases and historical metadata are preserved. The allocation ledger records the actual publication status of Version `2.10.2`, Build `0042`. The unpublished development value `1000` is excluded from the release baseline; installations using it need manual replacement.

Use [ReleaseBuilds.json](../Configuration/ReleaseBuilds.json) to retain the baseline and build allocations. Reuse a reservation for the same unfinished release attempt; allocate the next number for a new distributable build, retaining abandoned or distributed numbers. After publication, record the exact version/tag and mark the allocation `published`. Never reset the sequence by recounting or deleting releases.

Update both App target configurations, verify the actual bundle and signed feed preserve four digits, and use the previous global release build for update preparation (`0041` for this migration). Test-target versions are independent. Every future bilingual release note must state the complete version, padded Build, and their separate roles. Build visibility remains off by default under Developer Options. Stop before exceeding `9999` rather than wrapping or truncating.
