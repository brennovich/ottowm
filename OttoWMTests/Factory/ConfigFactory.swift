func makeConfig(_ bindings: [String: Action]) throws -> Config {
    Config(try bindings.reduce(into: [:]) { $0[try KeyCombo.parse($1.key).get()] = $1.value })
}
