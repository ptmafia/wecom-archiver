import Foundation
import Testing
@testable import WeComCore

private func t(_ v: String, x: Int = 640, w: Int = 300) -> AXItem { AXItem(r: "AXTextArea", v: v, x: x, w: w) }
private func s(_ v: String) -> AXItem { AXItem(r: "AXStaticText", v: v, x: 700, w: 70) }
private func b(_ v: String) -> AXItem { AXItem(r: "AXButton", v: v, x: 631, w: 50) }
private func avatar(_ x: Int = 593) -> AXItem { AXItem(r: "AXImage", v: "", x: x, w: 30) }
private let now = makeDate("2026-11-04 12:00")

@Suite struct RowParserTests {
    @Test func plainText() {
        let m = RowParser.assemble([[avatar(), b("佐藤"), s("9:34"), t("おはよう")]], selfName: "我", now: now)
        #expect(m.count == 1)
        #expect(m[0].sender == "佐藤")
        #expect(m[0].at == "2026-11-04 09:34")
        #expect(m[0].kind == .text)
        #expect(m[0].text == "おはよう")
    }
    @Test func rowWithoutTimeInheritsPrevious() {
        let m = RowParser.assemble([
            [avatar(), b("佐藤"), s("9:34"), t("一")],
            [avatar(), b("鈴木"), t("二")],
        ], selfName: "我", now: now)
        #expect(m[1].at == "2026-11-04 09:34")
    }
    @Test func aVideoLengthIsNotATime() {
        // A video shows its length (00:06) like a time; messages never go back in time, so it is not one.
        let video = AXItem(r: "AXImage", v: "", x: 640, w: 200)
        let m = RowParser.assemble([
            [avatar(), b("佐藤"), s("10:05"), t("一")],
            [avatar(), b("佐藤"), video, s("00:06")],
            [avatar(), b("佐藤"), t("二")],
        ], selfName: "我", now: now)
        #expect(m.map(\.at) == ["2026-11-04 10:05", "2026-11-04 10:05", "2026-11-04 10:05"])
    }
    @Test func quoteIsSeparatedFromMainText() {
        let m = RowParser.assemble([[avatar(), b("佐藤"), s("鈴木:"), t("元の発言"), t("返信"), b("ボタン")]], selfName: "我", now: now)
        #expect(m[0].text == "返信")
        #expect(m[0].quote == Quote(name: "鈴木", text: "元の発言"))
    }
    @Test func notifyListBeforeMainText() {
        let m = RowParser.assemble([[avatar(), b("佐藤"), t("鈴木、田中"), t("本文")]], selfName: "我", now: now)
        #expect(m[0].text == "本文")
        #expect(m[0].notify == "鈴木、田中")
    }
    @Test func avatarWithoutNameIsMe() {
        let m = RowParser.assemble([[avatar(1197), t("自分の発言")]], selfName: "我", now: now)
        #expect(m[0].sender == "我")
    }
    @Test func noAvatarIsSystemMessage() {
        let m = RowParser.assemble([[s("10月 15 14:55"), t("佐藤 が 鈴木 をグループに招待しました")]], selfName: "我", now: now)
        #expect(m[0].sender == "系统消息")
        #expect(m[0].kind == .system)
    }
    @Test func fileRow() {
        let m = RowParser.assemble([[avatar(), b("佐藤"), AXItem(r: "AXImage", v: "file pdf emphasize", x: 2, w: 2), s("平面図.pdf"), s("339K")]], selfName: "我", now: now)
        #expect(m[0].kind == .file)
        #expect(m[0].files == [Attachment(name: "平面図.pdf", size: "339K")])
    }
    @Test func imageRow() {
        let m = RowParser.assemble([[avatar(), b("佐藤"), AXItem(r: "AXImage", v: "", x: 640, w: 122)]], selfName: "我", now: now)
        #expect(m[0].kind == .image)
    }
    @Test func rowWithOnlyAvatarAndNameIsAnImage() {
        let m = RowParser.assemble([[avatar(), b("佐藤")]], selfName: "我", now: now)
        #expect(m.count == 1)
        #expect(m[0].kind == .image)
    }
    @Test func quotedFileIsNotAnAttachmentOfTheReply() {
        let m = RowParser.assemble([[avatar(), b("佐藤"), s("鈴木:"), AXItem(r: "AXImage", v: "file pdf", x: 2, w: 2), s("図.pdf"), s("14.0M"), s(""), t("返信"), b("ボタン")]], selfName: "我", now: now)
        #expect(m[0].kind == .text)
        #expect(m[0].text == "返信")
        #expect(m[0].files.isEmpty)
        #expect(m[0].quote == Quote(name: "鈴木", text: "［文件］図.pdf"))
    }
    @Test func quotedDocumentTitleIsKept() {
        let m = RowParser.assemble([[avatar(), b("佐藤"), s("鈴木:"), s("企画シート"), AXItem(r: "AXImage", v: "file sheet", x: 2, w: 2), t("返信"), b("ボタン")]], selfName: "我", now: now)
        #expect(m[0].text == "返信")
        #expect(m[0].quote == Quote(name: "鈴木", text: "企画シート"))
    }
    @Test func linkIsCollected() {
        let m = RowParser.assemble([[avatar(), b("佐藤"), t("見て"), AXItem(r: "AXLink", v: "https://example.com/a", x: 640, w: 100)]], selfName: "我", now: now)
        #expect(m[0].links == ["https://example.com/a"])
    }
    @Test func emptyRowsAreDropped() {
        #expect(RowParser.assemble([[], [t("  ", w: 0)]], selfName: "我", now: now).isEmpty)
    }
}

@Suite struct SingleChatTests {
    @Test func leftAvatarInSingleChatIsThePeer() {
        let m = RowParser.assemble([[AXItem(r: "AXImage", v: "icon user male h60", x: 593, w: 30), t("こんにちは")]], selfName: "我", peerName: "佐藤", now: now)
        #expect(m[0].sender == "佐藤")
    }
    @Test func fileNameIsNotMistakenForTime() {
        let m = RowParser.assemble([[avatar(), b("佐藤"), s("10月 15 18:53"), AXItem(r: "AXImage", v: "file pdf", x: 2, w: 2), s("図.pdf"), s("14.0M"), s(""), s("")]], selfName: "我", now: now)
        #expect(m[0].files == [Attachment(name: "図.pdf", size: "14.0M")])
        #expect(m[0].at == "2026-10-15 18:53")
    }
}

@Suite struct ArchiveTests {
    @Test func fileNameRemovesPathCharacters() {
        #expect(Archive.fileName("a/b:c") == "a_b_c.jsonl")
        #expect(Archive.fileName("") == "_.jsonl")
    }
    @Test func roundTrip() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let a = Archive(root: root); try a.prepare()
        let msg = Message(at: "2026-11-04 09:00", sender: "佐藤", kind: .file, text: "", files: [Attachment(name: "図.pdf", size: "1M")])
        try a.save("群", [msg])
        #expect(a.load("群") == [msg])
        try FileManager.default.removeItem(at: root)
    }
}
