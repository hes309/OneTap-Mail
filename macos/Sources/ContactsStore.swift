import Foundation
import Combine

struct Contact: Codable, Identifiable, Hashable {
    let id: UUID
    var email: String
    var name: String?
    var lastUsed: Date
    var useCount: Int

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? email : trimmed
    }

    var hasDisplayName: Bool {
        !(name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
final class ContactsStore: ObservableObject {
    static let shared = ContactsStore()

    @Published private(set) var contacts: [Contact] = []

    private let storageKey = "OneClickMail.contacts.v1"

    private init() {
        load()
    }

    func record(email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Validation.isEmail(trimmed) else { return }

        if let index = contacts.firstIndex(where: {
            $0.email.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            contacts[index].email = trimmed
            contacts[index].lastUsed = Date()
            contacts[index].useCount += 1
        } else {
            contacts.append(Contact(
                id: UUID(),
                email: trimmed,
                name: nil,
                lastUsed: Date(),
                useCount: 1
            ))
        }
        contacts.sort { $0.lastUsed > $1.lastUsed }
        persist()
    }

    func recent(limit: Int = 8) -> [Contact] {
        Array(contacts.prefix(limit))
    }

    func search(_ query: String) -> [Contact] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return contacts }
        return contacts.filter {
            $0.email.localizedCaseInsensitiveContains(keyword) ||
            ($0.name ?? "").localizedCaseInsensitiveContains(keyword)
        }
    }

    func updateName(_ name: String, for contact: Contact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        contacts[index].name = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    func remove(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Contact].self, from: data) else {
            return
        }
        contacts = saved.sorted { $0.lastUsed > $1.lastUsed }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
