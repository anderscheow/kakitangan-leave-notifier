import Contacts
import Foundation


/// Reads email addresses from the macOS address book for guest autocomplete.
enum MacContactsService {
    enum Access: Equatable {
        case notDetermined
        case authorized
        /// Denied, restricted, or blocked because the signed build lacks the Contacts entitlement.
        case unavailable
    }

    static var access: Access {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .unavailable
        @unknown default:
            // e.g. limited access on newer systems still lets us read the shared contacts.
            return .authorized
        }
    }

    static func requestAccess() async -> Access {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        return access
    }

    /// One suggestion per email address. Enumeration is synchronous, so it runs off the main actor.
    static func loadSuggestions() async -> [GuestSuggestion] {
        await Task.detached(priority: .utility) {
            let keys: [CNKeyDescriptor] = [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var suggestions: [GuestSuggestion] = []
            try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                let fullName = CNContactFormatter.string(from: contact, style: .fullName)
                let name = (fullName?.isEmpty == false ? fullName : nil) ?? (contact.organizationName.isEmpty ? nil : contact.organizationName)
                for address in contact.emailAddresses {
                    let email = address.value as String
                    if email.contains("@") {
                        suggestions.append(GuestSuggestion(email: email, name: name, source: .macContacts))
                    }
                }
            }
            return suggestions
        }.value
    }
}
