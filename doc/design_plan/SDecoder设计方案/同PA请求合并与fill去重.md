# 同 PA 请求合并 (merge queue) 与 fill 去重

状态: 讨论稿. 当前 RTL 已实现 SDTLB 的 fill 去重; merge queue 尚未实现.

## 背景

TLB 空或 `inv_all` 之后, 同一 PA 可能连续到达多次. 当前请求路径是:

```text
req -> SDTLB 查表 -> MISS_FIFO -> SDPTW -> SLMD_CALC -> RSP
                         |
                         +-> fill SDTLB
```

SDTLB 在第一个 fill 完成前一直不命中, 所以 4 个相同的 PA 会:

1. 写 4 个 MISS_FIFO 表项
2. 触发 4 次完全相同的 Page Walk
3. 产生 4 个 `miss_*` 结果
4. 触发 4 次 `fill_*`

第 3 步本身是功能正确的, 每个请求都会得到自己的响应; 问题在第 4 步: 如果 fill 只是按轮转指针分配条目, 就会在 SDTLB 里留下多个相同 tag 的有效表项.

之后同一个 PA 再查表时, `tag_hit_vector` 会有多个 bit 为 1:

- `req_hit` 仍为 1
- `onehot0_mux` 的数据选择不再可靠
- `a_tag_hit_vector_onehot0` 会失败

因此这里有两个独立问题:

| 问题 | 性质 | 当前处理 |
| --- | --- | --- |
| 4 次相同的 Page Walk | 性能 / 带宽 | 未处理 |
| 4 次相同的 fill 产生重复表项 | 功能正确性 | 已做 fill 去重 |
| 4 个请求的响应 | 功能正确性 | 各自按 `req_id` 返回 |

## 已实现的 fill 去重

SDTLB 在 fill 前先比较现有 tag:

```text
fill_hit_vector[i] =
    tag_item[i].valid &&
    tag_item[i].pa_base == fill_pa_base &&
    tag_item[i].pa_up   == fill_pa_up;
```

选择逻辑:

```text
fill_sel = |fill_hit_vector ? fill_hit_vector : victim_sel;
```

只有分配新条目时才步进 victim pointer:

```text
step = fill_valid && !(|fill_hit_vector);
```

这样:

- 第一次 fill 分配一个新条目
- 后续相同 tag 的 fill 更新同一个条目
- victim pointer 不会因为重复 fill 而多走
- 同一个 tag 最终只有一个有效表项

fill 去重不减少 Page Walk 次数, 但能保证 SDTLB 中不会出现重复 tag.

相关 RTL: [sdtlb.sv](../../../rtl/sdtlb.sv) 的 `fill_hit_vector` 与 `fill_sel`.

## 为什么 merge queue 值得单独讨论

fill 去重是正确性底线, 但它没有解决 4 次重复 walk 的带宽浪费. 如果 SDPTW 的本地表访问带宽紧张, 或者突发中相同页的 miss 很多, 就需要把同 PA 的请求合并到一次 walk.

merge queue (或 MSHR) 的目标:

1. 同一个 page base 在途时, 只保留一次 Page Walk
2. 每个请求仍然有自己的 `rsp_id`
3. 每个请求仍然得到一份响应
4. 只 fill 一次
5. 命中通路不受影响, 继续保持 hit-under-miss

不能简单地把重复请求丢掉, 因为协议要求每个 `req_id` 都有对应响应.

## 合并 key

### 按 `PA[47:30]` 合并

推荐首版使用 `PA[47:30]` 作为 key:

- Page Walk 只看 `PA[47:30]`
- 同一个 1GB 页的 L1 / L2 条目结果相同
- 一次 walk / 一次 fill 可以服务多个请求

但 `PA[29:0]` 会参与 SLA 低 30 位:

```text
SLA[29:0] = PA[29:0]
```

所以合并项里不能只存一个 `req_id`, 要保存每个请求的:

- `req_id`
- `PA[29:0]`

响应阶段用 walk 得到的 `S_PFN` / EID / TokenID 和每个请求自己的 `PA[29:0]` 重新拼 SLA.

### 按整条 PA 合并

按 `PA[47:0]` 合并实现最简单, 只服务完全相同的请求; 但两个页内偏移不同的请求本来可以共用同一次 walk, 合并率较低.

### 段式的情况

同一个段内不同 `PA[34:30]` 的请求:

- 它们共享同一个段式 fill tag (段基址 / 段上限)
- 但 SLA 高位的段内偏移不同

首版可以不按段合并, 只按 `PA[47:30]` 合并, 同段不同页仍各自 walk, 最终由 fill 去重合并到同一个段条目. 若以后要做段级合并, 合并 key 需要变成"段"而不是 1GB 页, 并额外保存每个请求的 `PA[34:30]`.

## 段式请求是反例

考虑一个 Type=1 的 32GB 区间 `R`, 段覆盖 `[4, 8]`, 同区间里还有页表. 两个请求都在段内, 但页号不同:

| 请求 | PA[47:35] | PA[34:30] | 命中路径 | 最终 fill tag |
| --- | --- | --- | --- | --- |
| A | R | 5 | 段内 | `{R, 4, 8}` |
| B | R | 6 | 段内 | `{R, 4, 8}` |

它们的 `PA[47:30]` 不同, 所以按 `PA[47:30]` 做的 merge queue 不会合并它们. 只要两个请求在第一次 fill 完成前都已经在途, 就会各走一次 walk, 各产生一个 fill.

如果只做 merge queue 而不做 fill 去重, 这两个 walk 的结果会写进两个不同 entry, 但它们其实是同一个段 tag. 之后同段请求仍然可能命中多个条目.

merge queue 在这里也帮不上忙:

- 按整条 PA 合并: A/B 的 PA 不同, 不合并
- 按 `PA[47:30]` 合并: A/B 的页号不同, 不合并
- 按最终 fill tag 合并: 请求阶段还不知道 `SEG_BASE` / `SEG_LEN`, 必须先读 L1; 请求侧 merge 无法直接使用这个 key

因此 fill 去重仍然必要. merge queue 只能减少页级重复 walk, 不能替代 SDTLB 对最终 fill tag 的去重.

如果以后做段级 merge, 可以在 L1 读回后把同段请求合并; 即便如此, 仍建议保留 fill 去重, 作为 SDTLB 的结构性 invariant.

## 结构方案

### 方案 A: 只做 fill 去重 (当前)

- 4 次 walk
- 4 次 fill, 但都更新同一个 entry
- 响应正确

优点: 结构最小, 已实现.

缺点: SDPTW 带宽浪费.

### 方案 B: 重复请求反压

在 SDTLB 未命中时, 比较请求 PA 和所有在途 miss; 如果同一个 PA 已在途, 拉低 `req_ready`, 等第一次 fill 完成后再接收.

优点:

- 不需要响应 fanout
- 不需要保存多个 `req_id`
- 实现比 merge queue 简单

缺点:

- 会阻塞上游, 且需要一个能比较所有在途 PA 的表
- 只能处理完全相同的请求
- 对突发不友好

### 方案 C: merge queue / MSHR

用一张在途表保存:

| 字段 | 说明 |
| --- | --- |
| `valid` | 表项有效 |
| `pa_base` | `PA[47:30]`, 合并 key |
| `state` | 等待 walk / 等响应 / 完成 |
| `id_list` | 挂接的 `req_id` 列表 |
| `offset_list` | 每个请求的 `PA[29:0]` |
| `id_count` | 已挂接请求数 |
| `fill_done` | 是否已经 fill |

请求路径:

```text
同 pa_base 的表项存在?
  是 -> 把 {req_id, PA[29:0]} 追加到该表项, 不写 MISS_FIFO
  否 -> 分配空表项, 写 MISS_FIFO / 启动 SDPTW, 记录第一个请求
```

walk 完成:

1. 根据 walk 结果 fill SDTLB 一次
2. 按 `id_list` 逐个生成响应, 每个响应用自己的 `req_id` 和 `PA[29:0]`
3. 响应 FIFO 满时保持 SDPTW DONE / 在途项, 等 `rsp_ready`
4. 所有响应取走后释放表项

需要注意:

- 响应 FIFO 只有 2 深; 一个合并项最多 4 个响应, 必须逐拍压入或在表项里保持
- `rsp_fcode` 异常时也要为每个挂接的请求各生成一个异常响应
- fill 只做一次, 但 fill 的 SLA / S_PFN / EID / TokenID 与具体请求的 `PA[29:0]` 无关; SLA 低位在响应阶段按每个请求补
- 在途表满时, 对新的不同 PA 反压 `req_ready`; 对同 PA 但 `id_list` 满的请求也要明确是反压还是再开一次 walk
- 如果请求在等 walk 期间被 `inv_*` 刷新, 要决定结果是否还允许 fill; 建议引入 epoch 或在 walk 结果上带有效代次

## 建议

首版保留当前结构:

1. SDTLB fill 去重作为正确性底线
2. 同 PA 请求仍然各自 walk, 各自响应
3. 用 directed test 保证不会出现重复 tag

后续如果 SDPTW 带宽成为瓶颈, 再做方案 C:

- key 用 `PA[47:30]`
- 在途表深度与 MISS_FIFO 对齐, 先按 4 项设计
- 每个请求保存 `req_id` 和 `PA[29:0]`
- 一次 walk / 一次 fill / 多份响应
- 段级合并作为后续增强

## 测试计划

### 已补的测试

- `tb_sdtlb`: 同一个 tag 连续 fill 4 次, 检查有效条目数仍为 1, 再请求确认命中唯一且数据是最后一次
- `TestSamePa`: TLB 空时连续发 4 个同 PA, 再发第 5 个; 检查 4 个 miss 响应和第 5 个响应; 并检查 page table model 的 AR 计数为 8 (4 次 walk 各 L1+L2), 第 5 个不再发 AR; 重复 tag 会由 `a_tag_hit_vector_onehot0` / `a_fill_hit_onehot0` 暴露

### merge queue 实现后需要补的测试

- 4 个同 PA 请求只触发一次 SDPTW walk (可用 walk 计数或 SDPTW 请求计数)
- 4 个请求各收到一个响应, `rsp_id` 一一对应
- 同 `PA[47:30]`、不同 `PA[29:0]`: 一次 walk, 4 份不同 SLA 低位
- 同段内不同 `PA[34:30]`: fill 去重后只有一条段条目
- 在途表满 / `id_list` 满时的反压
- 合并期间发生 `inv_all` / `inv_en` 的行为
- 同 PA merge 与命中通路并发时的乱序响应
