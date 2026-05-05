# Zellij Configuration Guide

## 为什么必须这样配置

Ghostty + Zellij + Claude Code 的组合如果不正确配置，会出现以下灾难：

1. **无限套娃**：`~/.zshrc` 里自动启动 zellij，但 zellij 内的 shell 又加载了同一份 `~/.zshrc`，导致递归启动 240+ 个进程，CPU 负载飙到 600+。
2. **平行世界 mirror**：多个 Ghostty 窗口 attach 到同一个 zellij session 时，所有窗口是 mirror 关系，`/clear` 会影响所有窗口，右上角计数器全局累加。
3. **配置漂移**：不同的启动方式（Ghostty command、手动 zsh、系统终端）加载不同的逻辑，导致 session 名不统一，难以管理。
4. **孤儿累积**（2026-05 实测）：终端窗口关闭后 zellij `--server` 进程不会自杀（zellij 设计如此），PPID 被 launchd 接走（=1）形成永久孤儿。同时 GUI App（如 CodexBar、IDE）若用 `zsh -l -i -c '...'` 抓 PATH，会触发完整 `.zshrc`，每次 App 启动 +1 zellij。13 天累积 50 个孤儿；任何 zellij bug 让其重新激活会复现 99% CPU 事故。

## 正确的工作流

### 每个 Ghostty 窗口 = 独立 Zellij Session

```
Ghostty Window 1          Ghostty Window 2          Ghostty Window 3
    |                           |                           |
    v                           v                           v
zsh -il                     zsh -il                     zsh -il
    |                           |                           |
    v                           v                           v
zellij --session gt-1234    zellij --session gt-5678    zellij --session gt-9012
    |                           |                           |
    v                           v                           v
[zellij 绿框]                [zellij 绿框]                [zellij 绿框]
    |                           |                           |
    v                           v                           v
claude                      claude                      claude
```

- 每个窗口有**独立的 zellij session**
- `/clear` 只影响**当前窗口**
- 关闭窗口后 session 变为 `EXITED`，下次开新窗口**自动清理**
- Claude Code 的历史记录是全局的（存储在 `~/.claude/`），换 session 照样能 resume

## 配置文件

### 1. Ghostty 配置 (`~/.config/ghostty/config`)

```ini
# 关键：只启动 zsh，让 zshrc 决定后续行为
command = zsh -il

# 禁用 macOS 窗口状态恢复，防止开机自动回到之前的 zellij session
window-save-state = never
```

**不要**在 Ghostty 里直接写 `command = env ZELLIJ_AUTO_START_GUARD=1 zsh -ilc "claude; exec zsh -i"`。
这会绕过 zshrc 的 zellij 启动逻辑，导致启动顺序混乱，出现"先启动 claude，再启动 zellij"的怪异行为。

### 2. Zsh 配置 (`~/.zshrc`)

```zsh
# Zellij auto-start: each terminal window gets its own independent session
if [[ $- == *i* ]] && [[ -t 0 ]] && [[ -z "$ZELLIJ" ]] && [[ -z "$CODEXBAR_PROBE" ]]; then
    # Clean EXITED + orphan running sessions (no client attached)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        name="${line%% *}"
        if [[ "$line" == *EXITED* ]]; then
            zellij delete-session "$name" --force 2>/dev/null
        elif [[ "$line" != *"(current)"* ]]; then
            zellij kill-session "$name" 2>/dev/null
            zellij delete-session "$name" --force 2>/dev/null
        fi
    done < <(zellij list-sessions -n 2>/dev/null)
    # Create a unique session for this terminal window
    zellij --session "gt-$$"
fi
```

**关键逻辑**（4 道闸门，缺一不可）：
- `[[ $- == *i* ]]`：只在**交互式 shell** 中启动，避免脚本/子进程误触发
- `[[ -t 0 ]]`：要求 **stdin 是真 TTY**。挡住 GUI App 用 `zsh -l -i -c '...'` 抓 PATH 的非 TTY 调用——没有这道闸门，每次 App 启动都会留一个 zellij 孤儿（参见上方"灾难 #4"）
- `[[ -z "$ZELLIJ" ]]`：只在**zellij 外部**启动，防止 zellij 内部的 shell 递归
- `[[ -z "$CODEXBAR_PROBE" ]]`：sentinel 逃生通道。GUI App 即使在 TTY 上调用，也可以通过 `Process.environment` 注入 `CODEXBAR_PROBE=1` 显式跳过
- `--session "gt-$$"`：以当前 shell PID 命名 session，确保每个窗口独立
- 清理逻辑同时处理 **EXITED** 和 **孤儿 running session**（终端早死、PPID=1 的 zellij --server）；`(current)` 标记的是当前 attached session，必须放过
- `list-sessions -n`：跳过 ANSI 染色，避免字符串匹配翻车

### 3. Zellij 配置 (`~/.config/zellij/config.kdl`)

```kdl
default_layout "compact"
```

配合自定义键位绑定，实现紧凑无边框布局。

## 常见误区

| 误区 | 后果 |
|------|------|
| `eval "$(zellij setup --generate-auto-start zsh)"` | zellij 官方脚本只有 `$ZELLIJ` 判断，在某些边界情况（如 pane 内新建 shell）会失效，导致无限套娃 |
| `zellij attach main` + 多个 Ghostty 窗口 | 所有窗口是同一个 session 的 mirror，内容完全同步，`/clear` 全局生效 |
| Ghostty `command` 里直接启动 claude | 启动顺序混乱，zellij 和 claude 互相阻塞，出现"需要按 Ctrl+Q 才能看到 claude"的诡异现象 |
| 缺少 `[[ $- == *i* ]]` 判断 | 非交互式 shell（如脚本、git hooks）也会启动 zellij，导致 CI/CD 或子命令卡死 |
| 缺少 `[[ -t 0 ]]` 判断 | GUI App（CodexBar / IDE 等）用 `zsh -l -i -c` 抓 PATH 时会触发完整 `.zshrc`，每次 App 启动 +1 zellij 孤儿，多日累积成几十上百个 PPID=1 的僵尸 |

## 快速诊断

如果怀疑 zellij 又在泛滥，按从轻到重的顺序排查：

```bash
# 1. 看活着的 session 名单（含状态、客户端数）
zellij list-sessions

# 2. 数当前 zellij 进程总数；正常应该等于「活着的 session 数」
ps -eo pid,command | grep "zellij --server" | grep -v grep | wc -l

# 3. 关键：找孤儿——PPID=1（被 launchd 接管）+ etime 过长（>1 天）
ps -eo pid,ppid,etime,command | grep "zellij --server" | grep -v grep
#   - PPID=1：原始终端早死，server 被 launchd 收养，无人看管
#   - etime 跨多天：长期累积的僵尸，CPU 看似 0% 但持续占 socket / FD / RAM

# 4. 紧急清理（确认当前没有重要会话在前台）
pkill -9 -f "zellij --server"
rm -rf "$(getconf DARWIN_USER_TEMP_DIR)zellij-$(id -u)"/*/gt-*
```

**回归信号**——下面任何一条出现就说明根因没修干净，回头检查 `.zshrc` 的 4 道闸门：
- `ps` 看到 `etime > 1天` 且 `PPID=1` 的 zellij --server
- `zellij list-sessions` 出现「非 EXITED、非 (current)」的 session 还赖在那里
- CPU 风扇异常 + Activity Monitor 看到 zellij 占 CPU

## 换电脑后的恢复步骤

1. 安装 Ghostty、Zellij、Claude Code
2. `cp -r ghostty ~/.config/`
3. `cp zellij/config.kdl ~/.config/zellij/`
4. 把 `zsh/zshrc.zsh` 的内容追加到 `~/.zshrc` 末尾
5. 完全退出并重新打开 Ghostty
