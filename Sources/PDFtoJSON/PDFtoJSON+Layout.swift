import Foundation
import Spanker
import Hitch

// Reading order by recursive XY-cut: a region is split at a vertical gutter (an empty
// strip through its full height) or at a horizontal gap larger than its normal line
// spacing; the leaves are blocks (column segments, boxes, paragraphs), and the order
// they are visited in is the reading order.

/// A line of text with its extent (output space, y up).
struct TextLine {
    let x: Double
    let x1: Double
    let y: Double
    let size: Double
    let text: String
    let horizontal: Bool

    var top: Double { y + 0.8 * size }
    var bottom: Double { y - 0.25 * size }
}

/// Top to bottom, then left to right; baselines within a fraction of the font size share a row.
func rowOrder(_ lines: [TextLine]) -> [TextLine] {
    let sorted = lines.sorted { $0.y > $1.y }
    var ordered: [TextLine] = []
    var row: [TextLine] = []
    for line in sorted {
        if let first = row.first, first.y - line.y > max(1.0, 0.3 * min(first.size, line.size)) {
            ordered.append(contentsOf: row.sorted { $0.x < $1.x })
            row = []
        }
        row.append(line)
    }
    ordered.append(contentsOf: row.sorted { $0.x < $1.x })
    return ordered
}

private func median(_ values: [Double]) -> Double {
    guard values.isEmpty == false else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

/// Short values flush against a common right edge (amounts, totals): the column of a
/// table, not a separate column of text.
private func isRightAlignedValues(_ lines: [TextLine], size: Double) -> Bool {
    guard lines.count >= 2 else { return false }
    let right = lines.map { $0.x1 }.max() ?? 0
    let flush = lines.filter { right - $0.x1 <= max(2.0, 0.3 * size) }.count
    let width = median(lines.map { $0.x1 - $0.x })
    return Double(flush) >= 0.6 * Double(lines.count) && width < 6 * size
}

/// Fraction of `lines` that share a baseline with some line in `other`.
private func pairedFraction(_ lines: [TextLine], _ other: [TextLine], size: Double) -> Double {
    let tolerance = max(1.0, 0.25 * size)
    let count = lines.filter { line in other.contains { abs($0.y - line.y) <= tolerance } }.count
    return Double(count) / Double(max(1, lines.count))
}

/// Do the two sides' lines pair up row by row (shared baselines)?
private func rowAligned(_ a: [TextLine], _ b: [TextLine], size: Double) -> Bool {
    return pairedFraction(a, b, size: size) >= 0.8 && pairedFraction(b, a, size: size) >= 0.8
}

/// Does this side contain table columns of its own (cells lining up with labels)?
private func hasTableColumns(_ lines: [TextLine], size: Double) -> Bool {
    guard lines.count >= 4 else { return false }
    for gap in verticalGutters(lines, minimum: max(5.0, 0.6 * size))
    where gap.first.count >= 2 && gap.second.count >= 2 {
        let (fewer, more) = gap.first.count <= gap.second.count ? (gap.first, gap.second) : (gap.second, gap.first)
        if pairedFraction(fewer, more, size: size) >= 0.8 {
            return true
        }
    }
    return false
}

/// The side's top line is set larger than the rest (a box or section heading).
private func startsWithHeading(_ lines: [TextLine]) -> Bool {
    guard let top = lines.max(by: { $0.y < $1.y }) else { return false }
    return top.size > 1.1 * median(lines.map { $0.size })
}

/// Should the region be read across this gutter, row by row (a table or a form),
/// rather than one side after the other (columns, side-by-side boxes)?
private func readAcross(_ gap: Gap, size: Double) -> Bool {
    // a column of amounts: the values of a table
    if isRightAlignedValues(gap.second, size: size) {
        return true
    }
    // sides whose lines don't correspond are independent columns
    guard rowAligned(gap.first, gap.second, size: size) else {
        return false
    }
    // rows line up: a table, a form, or columns that happen to share baselines
    if hasTableColumns(gap.first, size: size) || hasTableColumns(gap.second, size: size) {
        return true
    }
    let longLines = { (lines: [TextLine]) in median(lines.map { $0.x1 - $0.x }) >= 12 * size }
    if longLines(gap.first) && longLines(gap.second) {
        return false // article columns
    }
    if startsWithHeading(gap.first) && startsWithHeading(gap.second) {
        return false // side-by-side boxes
    }
    return true // label : value
}

private struct Gap {
    let size: Double
    let first: [TextLine]
    let second: [TextLine]
}

/// How many lines line up with the line nearest the gutter (left edges, centers or right
/// edges): the alignment that makes the lines beyond a gutter a column.
private func columnSupport(_ lines: [TextLine], size: Double) -> Int {
    guard let anchor = lines.min(by: { $0.x < $1.x }) else { return 0 }
    let tolerance = max(1.5, 0.2 * size)
    let center = (anchor.x + anchor.x1) / 2
    return lines.filter {
        abs($0.x - anchor.x) <= tolerance ||
        abs(($0.x + $0.x1) / 2 - center) <= tolerance ||
        abs($0.x1 - anchor.x1) <= tolerance
    }.count
}

/// Vertical gutters, widest first: (left lines, right lines).
private func verticalGutters(_ lines: [TextLine], minimum: Double) -> [Gap] {
    let sorted = lines.sorted { $0.x < $1.x }
    var gaps: [Gap] = []
    var maxRight = sorted.first?.x1 ?? 0
    for idx in 1..<sorted.count {
        let gap = sorted[idx].x - maxRight
        if gap >= minimum {
            gaps.append(Gap(size: gap, first: Array(sorted[..<idx]), second: Array(sorted[idx...])))
        }
        maxRight = max(maxRight, sorted[idx].x1)
    }
    return gaps.sorted { $0.size > $1.size }
}

/// Horizontal gaps, top to bottom: (lines above, lines below).
private func horizontalGaps(_ lines: [TextLine]) -> [Gap] {
    let sorted = lines.sorted { $0.top > $1.top }
    var gaps: [Gap] = []
    var minBottom = sorted.first?.bottom ?? 0
    for idx in 1..<sorted.count {
        let gap = minBottom - sorted[idx].top
        if gap > 0 {
            gaps.append(Gap(size: gap, first: Array(sorted[..<idx]), second: Array(sorted[idx...])))
        }
        minBottom = min(minBottom, sorted[idx].bottom)
    }
    return gaps
}

/// Split lines into blocks in reading order.
func readingOrderBlocks(_ lines: [TextLine], depth: Int = 0) -> [[TextLine]] {
    guard lines.count > 1, depth < 64 else { return lines.isEmpty ? [] : [lines] }
    let size = median(lines.map { $0.size })

    // the gutter that best separates two real columns: a column boundary is backed by
    // lines aligned where the gutter ends (left edges, centers or right edges), not just
    // by a gap that one stray item happens to sit after; width breaks ties
    var vertical: Gap? = nil
    var bestSupport = 0
    for gap in verticalGutters(lines, minimum: max(5.0, 0.6 * size)) {
        guard gap.first.count >= 2, gap.second.count >= 2 else { continue }
        let support = columnSupport(gap.second, size: size)
        guard support >= 2, support > bestSupport else { continue }
        guard readAcross(gap, size: size) == false else { continue }
        vertical = gap
        bestSupport = support
    }

    // the largest horizontal gap, if it is larger than this region's line spacing
    let gaps = horizontalGaps(lines)
    var horizontal: Gap? = nil
    if let largest = gaps.max(by: { $0.size < $1.size }) {
        let typical = median(gaps.map { $0.size })
        if largest.size >= max(0.5 * size, 1.4 * typical) || gaps.count == 1 && largest.size >= size {
            horizontal = largest
        }
    }

    let split: Gap?
    if let v = vertical, let h = horizontal {
        split = v.size >= 0.5 * h.size ? v : h
    } else {
        split = vertical ?? horizontal
    }
    guard let gap = split else { return [lines] }
    return readingOrderBlocks(gap.first, depth: depth + 1) + readingOrderBlocks(gap.second, depth: depth + 1)
}

private func lineElement(_ line: TextLine) -> JsonElement {
    let element = JsonElement(unknown: [:])
    element.set(key: "x", value: Int(line.x.rounded(.down)))
    element.set(key: "y", value: Int(line.y.rounded(.down)))
    element.set(key: "text", value: line.text)
    return element
}

func textElements(_ lines: [TextLine]) -> JsonElement {
    let output = JsonElement(unknown: [])
    for line in rowOrder(lines) {
        output.append(value: lineElement(line))
    }
    return output
}

/// [{ "x", "y", "width", "height", "text": [...] }] in reading order.
func blockElements(_ lines: [TextLine]) -> JsonElement {
    let horizontal = lines.filter { $0.horizontal }
    var blocks = readingOrderBlocks(horizontal)
    // rotated text is kept, one block per line, after the rest
    blocks += lines.filter { $0.horizontal == false }.map { [$0] }

    let output = JsonElement(unknown: [])
    for block in blocks where block.isEmpty == false {
        let x0 = block.map { $0.x }.min() ?? 0
        let x1 = block.map { $0.x1 }.max() ?? 0
        let bottom = block.map { $0.bottom }.min() ?? 0
        let top = block.map { $0.top }.max() ?? 0
        let element = JsonElement(unknown: [:])
        element.set(key: "x", value: Int(x0.rounded(.down)))
        element.set(key: "y", value: Int(bottom.rounded(.down)))
        element.set(key: "width", value: Int((x1 - x0).rounded(.up)))
        element.set(key: "height", value: Int((top - bottom).rounded(.up)))
        element.set(key: "text", value: textElements(block))
        output.append(value: element)
    }
    return output
}
