import Foundation
import MapKit


/// A place returned by Apple Maps autocomplete.
struct PlaceSuggestion: Identifiable, Hashable {
    let title: String
    let subtitle: String

    var id: String { "\(title)|\(subtitle)" }

    /// Text written into the meeting's location field.
    var locationText: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }
}


/// Apple Maps as-you-type place search. Free and keyless, unlike Google Places.
/// MapKit delivers completer callbacks on the main thread, hence the `@preconcurrency` conformance.
@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [PlaceSuggestion] = []

    private let completer = MKLocalSearchCompleter()
    private static let minimumQueryLength = 3

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength else {
            completer.cancel()
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
            .prefix(5)
            .map { PlaceSuggestion(title: $0.title, subtitle: $0.subtitle) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
