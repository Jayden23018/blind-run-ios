import XCTest
@testable import blindRun

/// 派单算法「显著告知」的两条红线。
///
/// 依据《互联网信息服务算法推荐管理规定》第十六条（不带「舆论属性或社会动员能力」前提，对我们直接生效）。
/// 后端已在隐私政策 §四完成「公示」那一半，App 内的「显著告知」这一半只能客户端做。
///
/// 这两条都不是「测一遍渲染」——它们守的是两件会被下一个人无意中改掉的事：
/// 告知出现在**正在被排序的那一刻**，以及告知里**不能出现具体权重**。
final class DispatchAlgorithmNoticeTests: XCTestCase {

    // MARK: - 状态集

    /// 告知只在「此刻真的有算法在替你排序」时出现。
    ///
    /// 逐 case 断言而不是只挑两个正例：`RunOrderStatus` 是开放枚举，
    /// 后端加值时 `offersDispatchAlgorithmNotice` 的穷举 switch 会逼一次决策，
    /// 而这条用例负责钉住那次决策的结果 —— 编译器只保证「你想过了」，不保证「你想对了」。
    func testNoticeIsOfferedOnlyWhileMatching() {
        let expected: Set<RunOrderStatus> = [.pendingMatch, .rematching]

        for status in RunOrderStatus.allCases {
            XCTAssertEqual(
                status.offersDispatchAlgorithmNotice,
                expected.contains(status),
                "状态 \(status.rawValue) 的匹配规则说明入口判定与预期不符"
            )
        }

        // `.unknown` 不在 `allCases` 里（见 `RunOrderStatus.allCases` 上那段注释），单独钉一次。
        XCTAssertFalse(
            RunOrderStatus.unknown.offersDispatchAlgorithmNotice,
            "未知状态不该给出算法说明入口 —— 我们并不知道那一刻发生了什么"
        )
    }

    // MARK: - 文案红线

    /// 🔴 **不得公示各维度的具体权重。**
    ///
    /// 后端红线，理由写在隐私政策 §四里：公开权重等于告诉人怎么有针对性地把自己的分数刷上去，
    /// 最终被挤掉的是老实排队的志愿者，等更久的是下单的盲人。
    ///
    /// 判据刻意**不是**「文案里不许出现『权重』二字」—— 正文里有一句
    /// 「我们不公示各个维度的具体权重」，那句是**必须在场**的。
    /// 真正要拦的是**把数值挂到某个排序维度上**，所以查的是百分号与「占比」。
    func testNoticeCopyDoesNotDiscloseRankingWeights() {
        let allCopy = Self.allNoticeCopy

        for forbidden in ["%", "％", "占比"] {
            XCTAssertFalse(
                allCopy.contains(forbidden),
                "匹配规则说明里出现了「\(forbidden)」—— 具体权重不得公示（后端红线）"
            )
        }

        XCTAssertTrue(
            allCopy.contains("不公示各个维度的具体权重"),
            "「不公示权重」这句本身必须留在文案里：删掉它，用户就无从知道我们是有意不说，而不是漏了"
        )
    }

    /// 「哪些信息不参与排序」四项逐项在场。
    ///
    /// 这四项与 `PrivacyConsentPurpose.blindVisionProfile` 的第 2 条、以及后端隐私政策 §四
    /// 是同一个口径。少一项就是**只在一处承诺、另一处不认**，而这两处用户都会读到。
    func testNoticeCopyListsFieldsExcludedFromRanking() {
        let allCopy = Self.allNoticeCopy

        for field in ["视力状况", "牵引方式", "姓名", "手机号"] {
            XCTAssertTrue(
                allCopy.contains("\(field)不参与排序"),
                "「\(field)不参与排序」不在文案里 —— 与隐私政策 §四 的公示口径对不上"
            )
        }

        // 导盲犬是**唯一**参与筛选但不参与排序的项，两件事必须同时说清。
        XCTAssertTrue(
            allCopy.contains("不影响先后次序"),
            "导盲犬只参与第一步筛选、不影响排序 —— 这句缺了，用户会以为带狗会被排到后面"
        )
    }

    /// 入口文案与页面文档能真的装配出来，且不是空的。
    ///
    /// 看着平凡，但它是「常量拆到 Copy 里之后被误删一半」的最小成本看门人：
    /// 空标题在界面上表现为一个**没有名字的按钮**，VoiceOver 念出来是一片空白。
    func testNoticeDocumentAssemblesWithNonEmptyCopy() {
        let document = DispatchAlgorithmNoticeCopy.document

        XCTAssertFalse(DispatchAlgorithmNoticeCopy.entryTitle.isEmpty)
        XCTAssertFalse(DispatchAlgorithmNoticeCopy.entryAccessibilityHint.isEmpty)
        XCTAssertFalse(document.title.isEmpty)
        XCTAssertFalse(document.notice.isEmpty)
        XCTAssertEqual(document.sections.count, 4)

        for section in document.sections {
            XCTAssertFalse(section.heading.isEmpty, "分节标题不能为空")
            XCTAssertFalse(section.bullets.isEmpty, "分节「\(section.heading)」一条正文都没有")
            for bullet in section.bullets {
                XCTAssertFalse(bullet.isEmpty, "分节「\(section.heading)」里有空白条目")
            }
        }
    }

    // MARK: - Helpers

    /// 把这一页所有会被用户看到 / 听到的字拼成一条，供文案红线扫描。
    private static var allNoticeCopy: String {
        let document = DispatchAlgorithmNoticeCopy.document
        return ([
            DispatchAlgorithmNoticeCopy.entryTitle,
            DispatchAlgorithmNoticeCopy.entryAccessibilityHint,
            document.title,
            document.notice
        ] + document.sections.flatMap { [$0.heading] + $0.bullets })
            .joined(separator: "\n")
    }
}
