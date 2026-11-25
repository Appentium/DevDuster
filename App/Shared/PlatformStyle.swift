import DusterCore

extension Rule.Platform {
    var systemImage: String {
        switch self {
        case .apple: "apple.logo"
        case .android: "smartphone"
        case .flutter: "bird"
        case .javascript: "curlybraces"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .rust: "gearshape.2"
        case .go: "hare"
        case .jvm: "cup.and.saucer"
        case .php: "server.rack"
        case .ruby: "diamond"
        case .dotnet: "number"
        case .otherLanguages: "character.book.closed"
        case .editors: "macwindow"
        case .aiTools: "sparkles"
        case .aiModels: "brain"
        case .gameEngines: "gamecontroller"
        case .devTools: "shippingbox"
        }
    }
}
