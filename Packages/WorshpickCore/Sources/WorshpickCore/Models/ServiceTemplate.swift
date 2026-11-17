import Foundation

public struct ServiceSlot: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var label: String
    public var moment: String?
    public var invitation: String?
    public var energy: Energy?

    public init(id: UUID = UUID(), label: String, moment: String? = nil, invitation: String? = nil, energy: Energy? = nil) {
        self.id = id
        self.label = label
        self.moment = moment
        self.invitation = invitation
        self.energy = energy
    }

    var criteriaDescription: String {
        var criteria: [String] = []
        if let moment { criteria.append("momento: \(moment)") }
        if let invitation { criteria.append("invitación: \(invitation)") }
        if let energy { criteria.append("energía: \(energy.rawValue)") }
        return criteria.isEmpty ? "sin criterios" : criteria.joined(separator: ", ")
    }
}

public struct ServiceTemplate: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var slots: [ServiceSlot]

    public init(id: UUID = UUID(), name: String, slots: [ServiceSlot]) {
        self.id = id
        self.name = name
        self.slots = slots
    }

    public static func withoutCriteria(songCount: Int) -> ServiceTemplate {
        ServiceTemplate(name: "Sin plantilla", slots: (1...max(1, songCount)).map { ServiceSlot(label: "Canción \($0)") })
    }

    public static let regularSunday = ServiceTemplate(
        id: UUID(uuidString: "5D1B1C8E-6F0B-4C55-9C43-6A1E0C7B2E01")!,
        name: "Domingo normal",
        slots: [
            ServiceSlot(label: "Apertura", moment: "Apertura", energy: .high),
            ServiceSlot(label: "Apertura", moment: "Apertura", energy: .high),
            ServiceSlot(label: "Adoración", moment: "Adoración"),
            ServiceSlot(label: "Adoración", moment: "Adoración", energy: .low),
            ServiceSlot(label: "Respuesta", moment: "Respuesta"),
        ]
    )
}
