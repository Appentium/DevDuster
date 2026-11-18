extension Sequence where Element: Sendable {
    func concurrentMap<T: Sendable>(limit: Int = 8, _ transform: @escaping @Sendable (Element) async -> T) async -> [T] {
        let elements = Array(self)
        return await withTaskGroup(of: (Int, T).self) { group in
            var results = [T?](repeating: nil, count: elements.count)
            for index in elements.indices {
                if index >= limit, let finished = await group.next() {
                    results[finished.0] = finished.1
                }
                let element = elements[index]
                group.addTask { (index, await transform(element)) }
            }
            for await finished in group {
                results[finished.0] = finished.1
            }
            return results.compactMap { $0 }
        }
    }
}
