// `scripts/hooks/guard/rules-copy.mjs` 的自测用例：内容规则 · 文案红线。
// 用例格式与运行方式见 `scripts/validate-guard.mjs`（exit 2 = 拦下，exit 0 = 放行）。

export const cases = [
  // placeholder-promise：起因是「积分商城」占位页在仓库里躺了很久，没有任何检查说过一句话。
  //
  // sos-copy 此前**一条自测都没有** —— 规则在 guard.mjs 里躺了很久，却没人验过它拦不拦得住。
  // 2026-08-13 补上，起因是行程告知功能用「家人」这个称呼，整条从原词表旁边绕了过去。
  //
  // 这几条走 post 模式：内容级规则是从磁盘读改动后的真实文件再查的（比解析 diff 可靠），
  // 所以用 `swift` 字段声明文件内容，由下面的 runner 落成临时文件。
  {
    name: '出货代码里承诺「敬请期待」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let title = "积分商城即将上线，敬请期待" }'
  },
  {
    name: '出货代码里承诺「即将上线」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let title = "该功能即将上线" }'
  },
  {
    // 占位 UI 本身不该被禁，如实说明当前不可用才是正确写法 ——
    // 规则拦的是「会兑现」的暗示，不是占位本身。
    name: '如实说明功能不可用（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let title = "这个功能还没有开放" }'
  },
  {
    name: 'SOS 文案宣称已通知紧急联系人（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let done = "已通知紧急联系人" }'
  },
  {
    // 换个称呼就穿过去，正是这条规则最容易被绕开的方式 —— 也正是它 2026-08-13 被绕开的方式。
    name: 'SOS 文案换用「家人」称呼（同样拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let sent = "已通知家人" }'
  },
  {
    name: 'SOS 文案说「家人已收到」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let sent = "家人已收到你的行程" }'
  },
  {
    // 进行时文案必须放行 —— 否则这条规则会把唯一正确的写法也堵死，
    // 逼着后来的人去加 guard:allow，那等于把规则关掉。
    name: '进行时文案「已交给系统短信」（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let sent = "短信已交给系统，请在短信里确认已发出。" }'
  },
  {
    name: '按钮文案「分享行程给家人」（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let buttonTitle = "分享行程给家人" }'
  },
  {
    // 注释里引用坏文案来解释「为什么要覆盖它」是我们希望留在代码里的东西。
    name: '注释里出现坏文案（放行）',
    mode: 'post',
    expect: 0,
    swift: '// 后端 body 写的是「已通知家人」，客户端必须用自己的进行时文案覆盖它。'
  },

  // volunteer-hours-credential：成就页把时长/星级说成凭据是违规（民政部令第 67 号），
  // 不是措辞问题。这条规则最容易出的错是把注册流程里合法的「资质证书」「实名认证」
  // 一起堵死 —— 下面四条放行用例就是钉这条边界的，删了它规则会变成噪音源。
  {
    name: '成就页把时长说成「服务证明」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let title = "志愿服务证明" }'
  },
  {
    name: '成就页把时长说成「时长证书」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let title = "导出你的服务时长证书" }'
  },
  {
    name: '成就页宣称「时长已认证」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let subtitle = "你的服务时长已认证" }'
  },
  {
    // 注册流程里的资质证书是真实动作，与服务时长的法律效力无关。堵死它等于把这条规则关掉。
    name: '注册流程的「资质证书」（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let title = "上传资质证书" }'
  },
  {
    name: '注册流程的「实名认证」（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let title = "请先完成实名认证" }'
  },
  {
    name: '注册流程的「培训证书」（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let hint = "上传助盲陪跑相关资质或培训证书" }'
  },
  {
    // 成就页真正该用的措辞。它必须放行，否则唯一正确的写法也过不去。
    name: '成就页的展示性措辞（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let d = "以上数据来自平台记录，供你自己查看。向学校或单位申报星级需要通过全国志愿服务信息系统办理。" }'
  },
  // call-verb-zhidian（#971）：按钮与播报一律「打电话」。
  {
    name: '按钮文案用「致电」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let call = "致电陪跑员" }'
  },
  {
    name: '播报句子里用「致电」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'func f(_ r: String) -> String { "你的上衣记录为\\(r)，如有误请致电更正。" }'
  },
  {
    name: '注释行里提到旧文案「致电」（放行）',
    mode: 'post',
    expect: 0,
    swift: '// 原文案是「致电陪跑员」，#971 改成「打电话给陪跑员」\nenum C { static let call = "打电话给陪跑员" }'
  },
  {
    name: '行尾注释里提到「致电」（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let call = "打电话给陪跑员" } // 原「致电陪跑员」'
  },
  {
    name: '「打电话」文案（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let again = "再打一次电话" }'
  }
];
