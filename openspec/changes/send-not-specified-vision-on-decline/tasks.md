## 1. 实现

- [x] 1.1 `VisionLevel` 增加 `notSpecified` 与 `escortDisplayName`
- [x] 1.2 资料页 ViewModel 记录「明确拒绝」，请求体按三种情形构造；`NOT_SPECIFIED` 回读为「不填」
- [x] 1.3 志愿者侧两处展示改用 `escortDisplayName`

## 2. 验证

- [ ] 2.1 新增用例通过，且生产代码回退到 main 时变红
- [ ] 2.2 `openspec validate --all --strict` 与 `validate-spec-coverage` 通过
