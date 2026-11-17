import Foundation

extension Array {
    /// Picks `count` elements spread evenly from first to last, keeping their order.
    public func evenlySpaced(count: Int) -> [Element] {
        guard count > 0 else { return [] }
        guard self.count > count else { return self }
        if count == 1 { return [self[0]] }
        let step = Double(self.count - 1) / Double(count - 1)
        return (0..<count).map { self[Int((Double($0) * step).rounded())] }
    }
}
