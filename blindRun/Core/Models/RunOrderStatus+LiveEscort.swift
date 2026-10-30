// 陪跑会话用的两条状态判定。放在单独的文件：`OrderDisplayHelpers.swift` 超了 SwiftLint 上限，棘轮不许它变长。
extension RunOrderStatus {
    /// 陪跑会话（`LiveEscortSessionCoordinator`）在这一态该不该跑 —— 推我方位置、
    /// 收对方位置、算走散告警，三件事共用这一个闸。
    ///
    /// 状态集与上面的 `fetchesVolunteerLocation` **恰好相同，但不复用它**，理由和
    /// `offersWaitedDuration` 不复用 `offersKeepWaiting` 是同一条：两者问的不是同一个问题。
    /// 上面那条问「后端给不给我**对方的**位置」，是照抄后端 `sharesLiveLocation()` 的；
    /// 这条问「我该不该**往上报我自己的**位置并维持会话」，两端角色都适用。
    /// 后端哪天只改其中一边（例如跨天预约临期开始预热位置），合成一处就会把另一边一起改掉。
    ///
    /// `.scheduledConfirmed` 不在内：`OrderModels.swift` 那条 case 的注释逐字写着
    /// 「实时位置**不推**（后端 `sharesLiveLocation()` 判 false）：距开跑还有几天，
    /// 推位置既无意义又是持续的位置泄露」。
    ///
    /// ⚠️ `.unknown` 判 false 是**沿用改动前的行为**，不是重新决策过的结论。
    /// 后端加了个我们还不认识的状态时，这条会让陪跑途中的位置上报静默停掉 ——
    /// 而实时位置是走散告警与求助定位的唯一来源。要不要像 `isActiveForBlindRunner`
    /// 那样对 `.unknown` 判 true（宁可多推也不要静默停），是一个待拍板的产品决定（#609）。
    /// **在那之前不要顺手改这一行**：多推位置本身也是泄露面。
    var runsLiveEscortSession: Bool {
        switch self {
        case .driverEnRoute, .driverArrived, .inProgress:
            return true
        case .pendingMatch, .pendingIntroCall, .pendingAccept, .scheduledConfirmed,
             .rematching, .noVolunteer, .completed, .cancelled:
            return false
        case .unknown:
            return false
        }
    }

    /// 这一态意味着「当前这个志愿者已经不是订单参与者了」，陪跑会话要就地清干净。
    ///
    /// **不是 `runsLiveEscortSession` 的反面**：`.pendingAccept` 两条都判 false ——
    /// 人已经接单但还没出发，既不该推位置，也不该把会话拆掉。
    ///
    /// `.rematching` 在内而它并不是终态：AGENTS.md 第 5 节逐字「`REMATCHING` 是已接单
    /// 志愿者取消后进入的状态……那个志愿者已不是订单参与者」。所以这条**不能**写成
    /// `isTerminal`，那条不含 `.rematching`，会把一个已经退出的人的会话留在原地继续推位置。
    var endsLiveEscortSession: Bool {
        switch self {
        case .completed, .cancelled, .rematching, .noVolunteer:
            return true
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept,
             .driverEnRoute, .driverArrived, .inProgress:
            return false
        case .unknown:
            return false
        }
    }
}
