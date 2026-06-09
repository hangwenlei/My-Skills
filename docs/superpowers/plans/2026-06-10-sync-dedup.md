# sync 去重 / 智能合并能力 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 `/sync:docs` 的步骤 4 加「跨文档去重/智能合并」能力（日志型跳过、可收敛/可合并、propose-confirm 标记后改），并给步骤 2 加 HANDOFF 自身去重。

**Architecture:** 本特性的「实现」是编辑指令文档 `plugins/sync/skills/docs/SKILL.md`（步骤 4 扩展 + 步骤 2 一句）。本项目的自动测试是结构校验脚本 `tests/validate-plugin.ps1`（正则断言 SKILL.md 含特定指令），用它充当「指令存在」的防回退护栏；功能行为靠手动在临时仓库跑 `/sync:docs` 验证。README 的 sync 描述同步更新以免自相矛盾。

**Tech Stack:** Markdown（SKILL.md / README.md）、PowerShell 5.1（校验脚本）、Git。

---

## 关键约束与坑（动手前必读）

- **`tests/validate-plugin.ps1` 必须保持 UTF-8 with BOM**。用 Edit 工具改它时只做局部字符串替换，不要整文件重写；改完**务必运行一次脚本**，确认中文 PASS/FAIL 消息不乱码（乱码=编码被破坏，需还原重改）。
- SKILL.md 用 Edit 工具替换指定区块即可，编码保持原样。
- 校验脚本用 `Get-Content ... -Encoding UTF8` 读 SKILL.md；断言用 `-match` 正则。新增断言的关键词必须与写进 SKILL.md 的中文**逐字一致**（如 `可收敛`、`可合并`、`日志型`、`同一事实只写一条`）。
- **不碰** `plugin.json` / `marketplace.json`（其 description 仍准确，去重是子行为，YAGNI）。
- 提交信息用中文，结尾带 `Co-Authored-By` trailer。

## 文件结构

- Modify: `tests/validate-plugin.ps1`（在 `if (Test-Path $sk2)` 块内新增 4 条 Check 断言）
- Modify: `plugins/sync/skills/docs/SKILL.md`（重写步骤 4 区块；步骤 2 末句追加一句）
- Modify: `README.md`（sync 小节「列出建议更新的其它文档」一行）
- 不新增文件。

---

## Task 1: 步骤 4 去重逻辑（结构护栏 + SKILL.md 改写）

**Files:**
- Modify: `tests/validate-plugin.ps1:57-62`
- Modify: `plugins/sync/skills/docs/SKILL.md:68-74`

- [ ] **Step 1: 写失败的结构断言（红）**

在 `tests/validate-plugin.ps1` 中，把现有的 sync SKILL.md 校验块（第 57–62 行）：

```powershell
if (Test-Path $sk2) {
  $c2 = Get-Content $sk2 -Raw -Encoding UTF8
  Check ($c2 -match '(?m)^name:\s*docs\s*$') 'sync SKILL.md name = docs'
  Check ($c2 -match 'disable-model-invocation:\s*true') 'sync SKILL.md disable-model-invocation = true'
  Check ($c2 -match 'HANDOFF\.md') 'sync SKILL.md 提及 HANDOFF.md'
}
```

替换为（新增 3 条去重断言；`同一事实只写一条` 留到 Task 2）：

```powershell
if (Test-Path $sk2) {
  $c2 = Get-Content $sk2 -Raw -Encoding UTF8
  Check ($c2 -match '(?m)^name:\s*docs\s*$') 'sync SKILL.md name = docs'
  Check ($c2 -match 'disable-model-invocation:\s*true') 'sync SKILL.md disable-model-invocation = true'
  Check ($c2 -match 'HANDOFF\.md') 'sync SKILL.md 提及 HANDOFF.md'
  Check ($c2 -match '可收敛') 'sync SKILL.md 步骤4 含去重类型「可收敛」'
  Check ($c2 -match '可合并') 'sync SKILL.md 步骤4 含去重类型「可合并」'
  Check ($c2 -match '日志型') 'sync SKILL.md 步骤4 含日志型跳过规则'
}
```

- [ ] **Step 2: 运行校验，确认新断言失败（红）**

Run: `powershell -ExecutionPolicy Bypass -File tests\validate-plugin.ps1`
Expected: 出现 3 行 `FAIL: sync SKILL.md 步骤4 含...`，末尾 `3 项失败`，退出码 1。中文消息不乱码。

- [ ] **Step 3: 改写 SKILL.md 步骤 4（绿）**

把 `plugins/sync/skills/docs/SKILL.md` 的步骤 4 区块（第 68–74 行）：

```markdown
## 步骤 4：刷新其它文档（先确认后改）

1. 基于步骤 1 的改动，扫描项目里**其它可能过时的文档**（如 README、设计/计划文档等手写 Markdown）。
2. 向用户**列出一张建议清单**，每项包含：文档路径、为什么需要更新、拟改要点。
3. **停下来等待用户确认**，让用户选择更新哪些（可全选、选部分、或都不改）。
4. **仅对用户确认的文档执行更新**；未确认的一律不改。
5. 本步骤不要执行 git commit。
```

整体替换为：

```markdown
## 步骤 4：刷新与收敛其它文档（先确认后改）

基于步骤 1 的改动，扫描项目里**其它可能过时或内容冗余的手写文档**（如 README、设计/计划文档、说明等）。本步骤同时处理「过时」与「跨文档冗余」，但全程只**列清单 + 等确认 + 只改确认项**，不自动改、不丢信息。

### 4.0 先给候选文档分类（决定能不能合并）
- **日志型 / 时间线型文档：一律跳过，不参与去重。** 命中任一即判定为日志型：
  - 文件名或一级标题含 `log`、`changelog`、`journal`、`日志`、`时间线`、`记录`、`ADR`、`decision`；
  - 或正文主体是带日期戳、按时间排列的条目列表。
- 其余**叙述型 / 状态型**文档（README、设计文档、说明等）才进入去重候选。

### 4.1 聚焦范围（保持轻量）
只比对「本次 session 改动 + 对话上下文实际涉及到的主题」所牵连的那几个叙述型文档，**不要对全项目所有文档做两两比对**。

### 4.2 识别两类问题，合并进同一张建议清单
- **过时**：文档内容与本次改动不符。
- **冗余 / 可合并**：
  - `可收敛`：两个及以上叙述型文档在讲同一事实 → 建议保留**权威出处**，其它处改成一句话 + 指针/链接。
  - `可合并`：某文档基本是另一文档的超集（B = A + 少量增量）→ 建议合并成一份，保留全部独有信息。

### 4.3 清单每项标注
- 文档路径；
- **类型**：`过时` / `可收敛` / `可合并`；
- 为什么；
- 拟改要点：收敛/合并时写明**保留方**、被收敛方改成什么，并声明「已核对独有信息不丢」。

### 4.4 护栏（执行确认项时必须遵守）
- **不丢信息**：执行收敛/合并前，逐条确认被收敛方的独有信息已在保留方出现；做不到就不动该项，只在清单里点出供用户决定。
- **受众边界**：受众不同的文档（如 README 面向用户、spec 面向开发者）默认**不物理合并**，只建议加指针，保住各自独立可读性。
- **权威出处**：面向用户的事实 → README；架构/设计决策 → spec/设计文档；当前开发现场 → HANDOFF；项目级长期约束 → CLAUDE.md。

### 4.5 收尾
- **停下来等待用户确认**（可全选、选部分、或都不改）。
- **仅对用户确认的文档执行更新**；未确认的一律不改。
- 本步骤不要执行 git commit。
```

- [ ] **Step 4: 运行校验，确认全绿**

Run: `powershell -ExecutionPolicy Bypass -File tests\validate-plugin.ps1`
Expected: 全部 `PASS`，末尾 `全部通过`，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add tests/validate-plugin.ps1 plugins/sync/skills/docs/SKILL.md
git commit -m "feat(sync): 步骤4 加跨文档去重/合并（日志型跳过、propose-confirm）

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: 步骤 2 HANDOFF 自身去重（结构护栏 + SKILL.md 一句）

**Files:**
- Modify: `tests/validate-plugin.ps1`（Task 1 改过的 sync 块内再加 1 条 Check）
- Modify: `plugins/sync/skills/docs/SKILL.md:57`

- [ ] **Step 1: 写失败的结构断言（红）**

在 `tests/validate-plugin.ps1` 的 sync SKILL.md 校验块里，`日志型` 那条断言之后、闭合 `}` 之前，新增一行：

```powershell
  Check ($c2 -match '同一事实只写一条') 'sync SKILL.md 步骤2 含 HANDOFF 自身去重'
```

- [ ] **Step 2: 运行校验，确认新断言失败（红）**

Run: `powershell -ExecutionPolicy Bypass -File tests\validate-plugin.ps1`
Expected: 出现 1 行 `FAIL: sync SKILL.md 步骤2 含 HANDOFF 自身去重`，末尾 `1 项失败`，退出码 1。

- [ ] **Step 3: 改 SKILL.md 步骤 2 末句（绿）**

把 `plugins/sync/skills/docs/SKILL.md` 第 57 行：

```markdown
内容要具体、可执行，避免空话套话。
```

替换为：

```markdown
内容要具体、可执行，避免空话套话；**同一事实只写一条，不在多个分节里重复出现。**
```

- [ ] **Step 4: 运行校验，确认全绿**

Run: `powershell -ExecutionPolicy Bypass -File tests\validate-plugin.ps1`
Expected: 全部 `PASS`，末尾 `全部通过`，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add tests/validate-plugin.ps1 plugins/sync/skills/docs/SKILL.md
git commit -m "feat(sync): 步骤2 HANDOFF 同一事实只写一条

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: README 同步去重描述（避免自相矛盾）

**Files:**
- Modify: `README.md:73`

- [ ] **Step 1: 改 README 的 sync 行为描述**

把 `README.md` 中 sync 小节的这一行（第 73 行）：

```markdown
- 列出建议更新的其它文档，经你确认后再改；
```

替换为：

```markdown
- 列出建议更新/收敛的其它文档（含跨文档去重，日志/时间线型自动跳过），经你确认后再改；
```

- [ ] **Step 2: 运行校验，确认未破坏结构**

Run: `powershell -ExecutionPolicy Bypass -File tests\validate-plugin.ps1`
Expected: 全部 `PASS`，末尾 `全部通过`，退出码 0。

- [ ] **Step 3: 提交**

```bash
git add README.md
git commit -m "docs: README 同步 sync 去重/收敛行为说明

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: 手动功能验证（无法自动化，由用户在真实 session 跑）

> `/sync:docs` 是 `disable-model-invocation: true` 的显式命令，只能由真实 Claude session 解释执行，自动化执行器跑不了。本任务是一张**手动验收清单**：在一个临时 git 仓库里逐条验证。无代码改动、不提交。

- [ ] **场景 1（可合并/超集）**：建文档 A 和文档 B，B 内容 = A + 一段独有内容。运行 `/sync:docs` → 建议清单出现 `可合并` 条目，拟改要点写明保留方且声明不丢独有内容；确认后合并结果包含两者全部独有信息。

- [ ] **场景 2（可收敛/重复事实）**：让 `README.md` 与某说明文档讲同一事实。运行 → 出现 `可收敛` 条目，建议保留权威出处、别处改指针。

- [ ] **场景 3（日志型跳过）**：建一个 `CHANGELOG.md`（或含日期条目的日志文档），且内容与别处重复。运行 → 该文档**不**出现在去重清单（被 4.0 分类跳过）。

- [ ] **场景 4（受众边界）**：让 `README.md`（面向用户）与某 spec（面向开发者）内容重叠。运行 → 默认建议加指针，而非物理合并。

- [ ] **场景 5（不确认即不改）**：对去重条目全不勾选 → 相关文档零改动。

- [ ] **场景 6（HANDOFF 自身去重）**：运行后检查生成的 `HANDOFF.md`，同一事实不在多个分节重复出现。

---

## Self-Review（计划对照 spec 的覆盖检查）

对照 `docs/superpowers/specs/2026-06-10-sync-dedup-design.md`：

- spec §3.1 文档分类（日志型跳过）→ Task 1 步骤 4 的 4.0；护栏 Task 1 的 4.4 ✅
- spec §3.1 聚焦范围 → Task 1 的 4.1 ✅
- spec §3.1 两类问题/清单标注（可收敛/可合并/过时）→ Task 1 的 4.2、4.3 ✅
- spec §3.1 三条护栏（不丢信息/受众边界/权威出处）→ Task 1 的 4.4 ✅
- spec §3.1 propose-confirm 不变项 → Task 1 的 4.5 ✅
- spec §3.2 HANDOFF 自身去重 → Task 2 ✅
- spec §5 测试 6 场景 → Task 4 全部覆盖；其中可自动化的「指令存在」部分由 Task 1/2 的结构断言守住 ✅
- spec §6 非目标 → 计划未引入全项目比对/自动合并/碰日志型/自动 commit，且 README 更新属「保持文档一致」非越界 ✅
- 占位符扫描：无 TBD/TODO，所有代码块为完整可粘贴内容 ✅
- 关键词一致性：SKILL.md 写入的 `可收敛`/`可合并`/`日志型`/`同一事实只写一条` 与校验脚本断言逐字一致 ✅
