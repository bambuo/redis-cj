# 发布流程

## 前置条件

- 工作区干净（无未提交修改）
- 所有功能开发和测试已完成，代码已合并到 `main` 分支

## 发布步骤

### 1. 更新版本号

```bash
bash scripts/generate_version.sh --write
```

自动根据当前日期生成版本号，格式为 `1.0.YYYYMMDD[-N]`（同日多次发布自动追加 `-N` 后缀）。

### 2. 提交版本变更并打 Tag

```bash
bash scripts/git_tag.sh --commit-version
```

- 自动提交 `cjpm.toml` 的版本号变更
- 自动生成 annotated tag `v1.0.YYYYMMDD`，包含 changelog

### 3. 构建发布包

```bash
bash scripts/build_release_from_tag.sh v1.0.YYYYMMDD
```

从 Tag 导出的源码树执行 `cjpm build` + `cjpm bundle`，产物输出到 `target/release-artifacts/v<version>/`。

> **macOS 已知问题：** `cjpm bundle` 因 stdx crypto SHA256 加载问题可能触发 SIGABRT。若遇到，可用以下方式绕过：
> ```bash
> # 从 Tag 导出源码到临时目录
> rm -rf /tmp/redis-cj-release && mkdir -p /tmp/redis-cj-release
> git archive --format=tar v1.0.YYYYMMDD | tar -x -C /tmp/redis-cj-release
> cd /tmp/redis-cj-release
> cjpm build --verbose
> cjpm bundle --skip-test --skip-lint
> cjpm publish
> ```

### 4. 发布到中央仓库

```bash
bash scripts/push_central.sh v1.0.YYYYMMDD
```

从 Tag 导出的源码树执行 `cjpm build` + `cjpm publish`。

> 注意：若第 3 步使用绕过方式，则跳过此步（`cjpm publish` 已在上步执行）。

### 一键发布

```bash
bash scripts/publish.sh all v1.0.YYYYMMDD
```

依次执行 build + push。

## 版本号规范

- 格式：`1.0.YYYYMMDD[-N]`
- 示例：`1.0.20260627`、`1.0.20260627-2`
- 由 `scripts/generate_version.sh` 自动管理，无需手动修改
