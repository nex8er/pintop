import AppKit

/// Minimal SVG path parser supporting the M/L/H/V/Z commands (absolute and relative),
/// which is all the Material Design Icons used by the app need.
enum SVGPath {
    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    static func bezierPath(_ d: String) -> NSBezierPath {
        let path = NSBezierPath()
        let tokens = tokenize(d)
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func nextNumber() -> CGFloat? {
            guard index < tokens.count, case .number(let value) = tokens[index] else { return nil }
            index += 1
            return value
        }

        while index < tokens.count {
            if case .command(let c) = tokens[index] {
                command = c
                index += 1
                if c == "Z" || c == "z" {
                    path.close()
                    current = start
                    continue
                }
            }
            let relative = command.isLowercase
            switch command.uppercased() {
            case "M":
                guard let x = nextNumber(), let y = nextNumber() else { return path }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.move(to: current)
                start = current
                command = relative ? "l" : "L" // Subsequent pairs are implicit line-tos.
            case "L":
                guard let x = nextNumber(), let y = nextNumber() else { return path }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.line(to: current)
            case "H":
                guard let x = nextNumber() else { return path }
                current.x = relative ? current.x + x : x
                path.line(to: current)
            case "V":
                guard let y = nextNumber() else { return path }
                current.y = relative ? current.y + y : y
                path.line(to: current)
            default:
                index += 1 // Unsupported command: skip its arguments.
            }
        }
        return path
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(d)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isLetter {
                tokens.append(.command(c))
                i += 1
            } else if c == "-" || c == "." || c.isNumber {
                var literal = String(c)
                var seenDot = c == "."
                i += 1
                while i < chars.count, chars[i].isNumber || (chars[i] == "." && !seenDot) {
                    if chars[i] == "." { seenDot = true }
                    literal.append(chars[i])
                    i += 1
                }
                tokens.append(.number(CGFloat(Double(literal) ?? 0)))
            } else {
                i += 1
            }
        }
        return tokens
    }
}
