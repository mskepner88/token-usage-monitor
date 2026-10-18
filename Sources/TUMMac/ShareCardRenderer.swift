import AppKit
import TUMCore
import UniformTypeIdentifiers

@MainActor
enum ShareCardRenderer {
    static func pngData(for card: UsageShareCard) -> Data? {
        let width: CGFloat = 720
        let padding: CGFloat = 28
        let rowHeight: CGFloat = 58
        let detailHeight: CGFloat = 16
        let header: CGFloat = 78
        let footer: CGFloat = 72
        let details = card.rows.reduce(0) { $0 + $1.details.count }
        let height = header + CGFloat(card.rows.count) * rowHeight + CGFloat(details) * detailHeight + footer

        let size = NSSize(width: width, height: max(height, 180))
        let image = NSImage(size: size, flipped: false) { rect in
            draw(card: card, in: rect, padding: padding, rowHeight: rowHeight, detailHeight: detailHeight)
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return png
    }

    static func copyToPasteboard(_ data: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        if let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        }
    }

    static func promptSave(_ data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "TUM-snapshot.png"
        panel.title = "Save TUM snapshot"
        panel.prompt = "Save"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func draw(
        card: UsageShareCard,
        in rect: NSRect,
        padding: CGFloat,
        rowHeight: CGFloat,
        detailHeight: CGFloat
    ) {
        NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
        NSBezierPath(rect: rect).fill()

        let title = "TUM" as NSString
        let titleFont = NSFont.systemFont(ofSize: 26, weight: .bold)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.white,
        ]
        title.draw(at: NSPoint(x: padding, y: rect.height - padding - 28), withAttributes: titleAttrs)

        let pitch = SkeptacularBrand.pitch as NSString
        pitch.draw(
            at: NSPoint(x: padding, y: rect.height - padding - 50),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor(calibratedWhite: 0.68, alpha: 1),
            ]
        )

        var y = rect.height - padding - 78
        let contentWidth = rect.width - padding * 2
        for row in card.rows {
            let name = row.providerName as NSString
            name.draw(
                at: NSPoint(x: padding, y: y - 18),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: NSColor.white,
                ]
            )
            let percent = (row.percentLabel.isEmpty ? "—" : row.percentLabel) as NSString
            let percentSize = percent.size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            ])
            percent.draw(
                at: NSPoint(x: rect.width - padding - percentSize.width, y: y - 18),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: NSColor.white,
                ]
            )

            let barY = y - 36
            let fractions = row.percentsLeft.isEmpty ? [0.0] : row.percentsLeft.map { Double($0) / 100 }
            let gap: CGFloat = 8
            let barWidth = (contentWidth - gap * CGFloat(max(fractions.count - 1, 0))) / CGFloat(fractions.count)
            let accent = nsColor(hex: row.accentHex)
            for (index, fraction) in fractions.enumerated() {
                let x = padding + CGFloat(index) * (barWidth + gap)
                let track = NSRect(x: x, y: barY, width: barWidth, height: 8)
                NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
                NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
                let fillWidth = max(0, min(barWidth, barWidth * CGFloat(fraction)))
                if fillWidth > 0 {
                    accent.setFill()
                    NSBezierPath(
                        roundedRect: NSRect(x: x, y: barY, width: fillWidth, height: 8),
                        xRadius: 4,
                        yRadius: 4
                    ).fill()
                }
            }

            y -= rowHeight
            for detail in row.details {
                (detail as NSString).draw(
                    at: NSPoint(x: padding, y: y - 4),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1),
                    ]
                )
                y -= detailHeight
            }
        }

        let mark = card.brandMark as NSString
        let markFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let markSize = mark.size(withAttributes: [.font: markFont])
        mark.draw(
            at: NSPoint(x: rect.width - padding - markSize.width, y: 18),
            withAttributes: [
                .font: markFont,
                .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1),
            ]
        )
    }

    private static func nsColor(hex: String) -> NSColor {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return .white
        }
        return NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
