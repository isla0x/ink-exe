// ink.exe 홈 화면 · 잠금화면 위젯
//
// 앱과 데이터를 나누지 않고, 위젯이 서버의 board_status() 를 직접 부른다 (로그인 필요 없음).
//   → 오늘 글감 · 몇 명 썼는지 · 자정까지 남은 시간 · 지금 1위 글
// 서버 함수는 supabase/schema.sql 의 board_status. 키는 앱(lib/config.dart)과 같은 공개용 키.
//
// 지원 크기
//   홈 화면   : 작게 / 중간
//   잠금 화면 : 직사각형 / 원형 / 시계 위 한 줄 (todo.exe · diary.exe 와 같은 모양)
//
// 새로 고침: 20분마다 + 자정 직후 (iOS 가 하루 횟수를 조절한다). 인터넷이 안 되면 마지막으로 받은 것을 보여준다.

import SwiftUI
import WidgetKit

private let serverURL = "https://eqadkyrdcpdjomvhpkgi.supabase.co"
private let publishableKey = "sb_publishable_AbU7JlZV_FAoXJXdwE9egg_YUKtu94V"
private let cacheKey = "ink_widget_status_v1"
private let seoul = TimeZone(identifier: "Asia/Seoul") ?? .current

// MARK: - 데이터

struct TopPost: Codable, Hashable {
    let slot: Int
    let nick: String
    let body: String?
    let likes: Int
    let kind: String?
    let src_title: String?
    let src_author: String?

    var isQuote: Bool { kind == "quote" }
}

struct BoardStatus: Codable {
    /// 한국 시간 날짜 "2026-10-01"
    let day: String
    let topic: String
    let cap: Int
    let count: Int
    let seconds_left: Int
    let top: TopPost?
}

/// 받아 온 요약 + 받은 시각. 마감 시각은 받은 시각 + seconds_left.
struct Snapshot: Codable {
    let status: BoardStatus
    let fetchedAt: Date

    var deadline: Date { fetchedAt.addingTimeInterval(TimeInterval(status.seconds_left)) }

    /// 마감(자정)이 지났으면 이 요약은 어제 것이다.
    func isStale(at date: Date) -> Bool { date >= deadline }

    static let sample = Snapshot(
        status: BoardStatus(
            day: "2026-10-01", topic: "파란 나무", cap: 20, count: 12, seconds_left: 13 * 3600 + 52 * 60,
            top: TopPost(slot: 4, nick: "guest_1903", body: "뿌리는 기억을 먹고 자란다. 그래서 오래된 나무일수록 푸르다.",
                         likes: 21, kind: "original", src_title: nil, src_author: nil)
        ),
        fetchedAt: .now
    )
}

enum StatusStore {
    static func load() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ s: Snapshot) {
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: cacheKey) }
    }

    static func fetch() async -> Snapshot? {
        guard let url = URL(string: "\(serverURL)/rest/v1/rpc/board_status") else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue(publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            guard (res as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let status = try JSONDecoder().decode(BoardStatus.self, from: data)
            let snap = Snapshot(status: status, fetchedAt: .now)
            save(snap)
            return snap
        } catch {
            return nil
        }
    }
}

// MARK: - 도우미

private func formatter(_ format: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = seoul
    f.dateFormat = format
    return f
}

/// "2026-10-01" → "10.01 목"
private func shortDay(_ key: String) -> String {
    guard let d = formatter("yyyy-MM-dd").date(from: key) else { return key }
    return formatter("MM.dd E").string(from: d)
}

/// [██████░░░░]
private func bar(_ count: Int, _ cap: Int, width: Int = 10) -> String {
    let n = cap > 0 ? min(width, Int((Double(count) / Double(cap) * Double(width)).rounded())) : 0
    return "[" + String(repeating: "█", count: n) + String(repeating: "░", count: width - n) + "]"
}

private func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
}

// MARK: - 색 (앱의 cmd 팔레트, 밝은 모드는 종이 출력 느낌)

struct TermColors {
    let bg, bar, fg, hi, dim, tag, cmd, warn, line: Color

    static func of(light: Bool) -> TermColors {
        if light {
            return TermColors(bg: Color(hex: 0xF5F2E8), bar: Color(hex: 0xE8E4D6), fg: Color(hex: 0x2B2B2B),
                              hi: Color(hex: 0x111111), dim: Color(hex: 0x6B6B6B), tag: Color(hex: 0x7A5F00),
                              cmd: Color(hex: 0x0B6E8A), warn: Color(hex: 0xC0282F), line: Color(hex: 0xD6D1C2))
        }
        return TermColors(bg: Color(hex: 0x0C0C0C), bar: Color(hex: 0x1A1A1A), fg: Color(hex: 0xCCCCCC),
                          hi: Color(hex: 0xF2F2F2), dim: Color(hex: 0xA3A3A3), tag: Color(hex: 0xF9F1A5),
                          cmd: Color(hex: 0x61D6D6), warn: Color(hex: 0xE74856), line: Color(hex: 0x2A2A2A))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - 타임라인

struct InkEntry: TimelineEntry {
    let date: Date
    /// nil = 한 번도 못 받아 옴 (처음 + 오프라인)
    let snap: Snapshot?

    /// 자정이 지나 새 글감을 아직 못 받은 상태
    var stale: Bool { snap?.isStale(at: date) ?? true }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> InkEntry {
        InkEntry(date: .now, snap: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (InkEntry) -> Void) {
        if context.isPreview {
            completion(InkEntry(date: .now, snap: .sample))
            return
        }
        Task {
            let snap = await StatusStore.fetch() ?? StatusStore.load()
            completion(InkEntry(date: .now, snap: snap))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InkEntry>) -> Void) {
        Task {
            let now = Date()
            let fetched = await StatusStore.fetch()
            let snap = fetched ?? StatusStore.load()
            var entries = [InkEntry(date: now, snap: snap)]
            // 20분 뒤, 또는 자정 10초 뒤 (새 글감) 중 빠른 쪽에 다시 받는다. 못 받았으면 5분 뒤 다시.
            var next = now.addingTimeInterval(fetched == nil ? 5 * 60 : 20 * 60)
            if let s = snap, s.deadline > now {
                let afterMidnight = s.deadline.addingTimeInterval(10)
                // 자정이 지나면 '새 글감 여는 중' 으로 바뀐 화면을 미리 넣어 둔다.
                entries.append(InkEntry(date: s.deadline, snap: s))
                next = min(next, afterMidnight)
            }
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }
}

// MARK: - 공통 조각

struct TitleStrip: View {
    let c: TermColors
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(">_").font(mono(11, .bold)).foregroundColor(c.hi)
            Text("ink.exe").font(mono(11)).foregroundColor(c.hi)
            Spacer(minLength: 4)
            if let t = trailing {
                Text(t).font(mono(10)).foregroundColor(c.dim).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(c.bar)
    }
}

/// 글감 · 접속 막대 · 남은 자리 · 마감 카운트다운
struct BoardBlock: View {
    let entry: InkEntry
    let c: TermColors
    var topicSize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let s = entry.snap, !entry.stale {
                let st = s.status
                let full = st.count >= st.cap
                (Text("C:\\ink> ").foregroundColor(c.dim) + Text("topic").foregroundColor(c.cmd))
                    .font(mono(10))
                Text(st.topic)
                    .font(mono(topicSize, .bold))
                    .foregroundColor(c.hi)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(bar(st.count, st.cap)).font(mono(11)).foregroundColor(full ? c.warn : c.cmd).lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    Text("\(st.count)/\(st.cap)").font(mono(11, .bold)).foregroundColor(c.hi)
                    Text(full ? "FULL" : "남은 \(st.cap - st.count)")
                        .font(mono(11)).foregroundColor(full ? c.warn : c.dim)
                }
                .lineLimit(1)
                HStack(spacing: 4) {
                    Text(full ? "다음" : "마감").font(mono(10)).foregroundColor(c.dim)
                    Text(timerInterval: entry.date...max(entry.date, s.deadline), countsDown: true)
                        .font(mono(10))
                        .foregroundColor(c.tag)
                        .monospacedDigit()
                }
                .lineLimit(1)
            } else if entry.snap != nil {
                // 자정이 지났는데 아직 새 글감을 못 받음
                (Text("C:\\ink> ").foregroundColor(c.dim) + Text("topic").foregroundColor(c.cmd)).font(mono(10))
                Text("새 글감 여는 중...").font(mono(13, .bold)).foregroundColor(c.hi).lineLimit(2)
                Spacer(minLength: 0)
                Text("선착순 20명, 지금 시작").font(mono(10)).foregroundColor(c.dim).lineLimit(1)
            } else {
                (Text("C:\\ink> ").foregroundColor(c.dim) + Text("connect").foregroundColor(c.cmd)).font(mono(10))
                Text("NO CARRIER").font(mono(14, .bold)).foregroundColor(c.warn)
                Spacer(minLength: 0)
                Text("인터넷 연결 후\n잠시 뒤 다시 불러와요").font(mono(10)).foregroundColor(c.dim).lineLimit(2)
            }
        }
    }
}

// MARK: - 홈 화면 위젯

struct SmallView: View {
    let entry: InkEntry
    let c: TermColors

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleStrip(c: c, trailing: entry.snap.map { shortDay($0.status.day) })
            BoardBlock(entry: entry, c: c, topicSize: 18)
                .padding(.horizontal, 12)
                .padding(.top, 7)
                .padding(.bottom, 10)
        }
    }
}

struct MediumView: View {
    let entry: InkEntry
    let c: TermColors

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleStrip(c: c, trailing: entry.snap.map { shortDay($0.status.day) })
            HStack(alignment: .top, spacing: 12) {
                BoardBlock(entry: entry, c: c, topicSize: 18)
                    .frame(width: 128, alignment: .leading)

                Rectangle().fill(c.line).frame(width: 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("지금 1위").font(mono(10)).foregroundColor(c.dim)
                    if !entry.stale, let top = entry.snap?.status.top, let body = top.body {
                        Text(body).font(mono(12)).foregroundColor(c.hi).lineLimit(top.isQuote ? 3 : 4)
                        if top.isQuote, let t = top.src_title {
                            Text("— 『\(t)』, \(top.src_author ?? "")").font(mono(10)).foregroundColor(c.tag).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Text("#\(String(format: "%02d", top.slot))").font(mono(10)).foregroundColor(c.dim)
                            Text(top.nick).font(mono(10)).foregroundColor(c.fg).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("+\(top.likes)").font(mono(10, .bold)).foregroundColor(c.cmd)
                        }
                    } else {
                        Text("아직 +1 받은 글이 없어요.\n첫 한 편의 주인공이 되어 보세요.")
                            .font(mono(11)).foregroundColor(c.dim).lineLimit(3)
                        Spacer(minLength: 0)
                        (Text("C:\\ink> ").foregroundColor(c.dim) + Text("write").foregroundColor(c.cmd) + Text("_").foregroundColor(c.tag))
                            .font(mono(11))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - 잠금화면 위젯

/// 직사각형: 3줄 터미널 (todo.exe · diary.exe 와 같은 모양)
///   C:\ink> 12/20
///   > 파란 나무
///   > 마감 13:52:01
struct LockRectView: View {
    let entry: InkEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let s = entry.snap, !entry.stale {
                let st = s.status
                let full = st.count >= st.cap
                Text("C:\\ink> " + (full ? "FULL" : "\(st.count)/\(st.cap)"))
                    .font(mono(13, .bold))
                    .widgetAccentable()
                Text("> " + st.topic)
                    .font(mono(12))
                    .lineLimit(1)
                HStack(spacing: 0) {
                    Text(full ? "> 다음 " : "> 마감 ").font(mono(12))
                    Text(timerInterval: entry.date...max(entry.date, s.deadline), countsDown: true)
                        .font(mono(12))
                        .monospacedDigit()
                }
                .lineLimit(1)
            } else {
                Text("C:\\ink> topic")
                    .font(mono(13, .bold))
                    .widgetAccentable()
                Text(entry.snap == nil ? "> 연결 중..." : "> 새 글감 여는 중...").font(mono(12)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 원형: 남은 자리 + 찬 자리 링 (todo.exe 와 같은 모양)
struct LockCircleView: View {
    let entry: InkEntry

    var body: some View {
        if let s = entry.snap, !entry.stale {
            let st = s.status
            Gauge(value: Double(min(st.count, st.cap)), in: 0...Double(max(st.cap, 1))) {
                Text(">_").font(mono(10))
            } currentValueLabel: {
                Text("\(max(st.cap - st.count, 0))").font(mono(18, .bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Text(">_").font(mono(14, .bold))
            }
            .widgetAccentable()
        }
    }
}

struct LockInlineView: View {
    let entry: InkEntry

    var body: some View {
        if let s = entry.snap, !entry.stale {
            Text(">_ \(s.status.topic) · \(s.status.count)/\(s.status.cap)")
        } else {
            Text(">_ ink.exe")
        }
    }
}

// MARK: - 위젯 정의

struct InkWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: InkEntry

    private var colors: TermColors { TermColors.of(light: scheme == .light) }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            LockRectView(entry: entry).containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            LockCircleView(entry: entry).containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            LockInlineView(entry: entry).containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            MediumView(entry: entry, c: colors).containerBackground(for: .widget) { colors.bg }
        default:
            SmallView(entry: entry, c: colors).containerBackground(for: .widget) { colors.bg }
        }
    }
}

struct InkWidget: Widget {
    let kind = "InkWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            InkWidgetView(entry: entry)
        }
        .configurationDisplayName("ink.exe")
        .description("오늘의 글감, 남은 자리, 마감까지 남은 시간.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

// MARK: - Xcode 미리보기

#Preview("작게", as: .systemSmall) {
    InkWidget()
} timeline: {
    InkEntry(date: .now, snap: .sample)
}

#Preview("중간", as: .systemMedium) {
    InkWidget()
} timeline: {
    InkEntry(date: .now, snap: .sample)
}

#Preview("오프라인", as: .systemSmall) {
    InkWidget()
} timeline: {
    InkEntry(date: .now, snap: nil)
}

#Preview("잠금 직사각형", as: .accessoryRectangular) {
    InkWidget()
} timeline: {
    InkEntry(date: .now, snap: .sample)
}

#Preview("잠금 원형", as: .accessoryCircular) {
    InkWidget()
} timeline: {
    InkEntry(date: .now, snap: .sample)
}
